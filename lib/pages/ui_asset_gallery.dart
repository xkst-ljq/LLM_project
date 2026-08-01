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
    // 只展示作者自己保存的资产。
    //
    // 内置引擎原子（文本、按钮、滑块……）是所有 UI 的默认元素，
    // 工作台左侧「原材料」区随时能取用，在成品库里再陈列一遍纯属噪音。
    // getUserModules 正常会返回空表——_modules 里只有引擎原子，
    // 它只在兜底旧存档时才有内容。
    final modules = _assetService.getUserModules();
    final composites = _assetService.getAllComposites();
    final isEmpty = modules.isEmpty && composites.isEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
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
                // 两个分区各自空判断：只存过复合件时，不该留一个空的
                // 「自定义模组」标题杵在上面。
                if (modules.isNotEmpty) ...[
                  _sectionTitle('自定义模组'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: modules.map(_buildModuleCard).toList(),
                  ),
                  const SizedBox(height: 24),
                ],
                if (composites.isNotEmpty) ...[
                  _sectionTitle('复合组件'),
                  const SizedBox(height: 4),
                  const Text(
                    '按设计时的原始比例展示，可直接在卡片里试用交互。',
                    style: TextStyle(fontSize: 11, color: Color(0xFF888896)),
                  ),
                  const SizedBox(height: 12),
                  // 每个复合件独占一行：它们尺寸各异，塞进 Wrap 会因为
                  // 行高被最高的那个撑开而留下大片空白。
                  ...composites.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildCompositeCard(c),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black54,
            ),
      );

  Widget _buildModuleCard(UIModule m) {
    final element = UIElement(id: m.id, isComposite: false, module: m);
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
  }

  /// 单个复合组件卡片：独立边框 + 原始比例 + 可交互预览。
  Widget _buildCompositeCard(UIComposite c) {
    final element = UIElement(id: c.id, isComposite: true, composite: c);

    // 设计时的自然尺寸。compositeNaturalSize 取子元素包围盒的右下边界
    // （左上留白也算布局的一部分），正是作者在工作台上看到的尺寸。
    final natural = UIRenderer.compositeNaturalSize(c);

    return LayoutBuilder(
      builder: (context, constraints) {
        // 卡片内边距 12×2 + 边框，留出余量。
        final available = constraints.maxWidth - 26;
        // 只在超出可用宽度时才缩小，**绝不放大**——放大会让描边糊掉，
        // 也会让作者误判组件的真实体量。
        final scale = (natural.width > available && available > 0)
            ? available / natural.width
            : 1.0;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0x14000000)),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预览区：给足自然尺寸 × 缩放后的位置，避免相邻卡片重叠。
              SizedBox(
                width: natural.width * scale,
                height: natural.height * scale,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: natural.width,
                    height: natural.height,
                    child: UILinkerSnapshotScope(
                      snapshot: LinkerSnapshot.fromElements([element]),
                      // isStudioCreationMode: false —— 这是**运行时**语义。
                      //
                      // 传 true 会让渲染器把 linker / math_node / timer
                      // 当作编辑期后台节点跳过（见 _renderComposite 的
                      // backendTypes 分支），于是拖了滑块也不会驱动进度条，
                      // 交互形同虚设。这里要的正是「能像真机一样玩一玩」。
                      child: UISceneModeScope(
                        isStudioCreationMode: false,
                        // 不套 IgnorePointer：让用户直接点按钮、拖滑块。
                        child: Builder(
                          builder: (ctx) => UIRenderer.render(ctx, element),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0x0F000000)),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF111116),
                          ),
                        ),
                        Text(
                          // 标出原始尺寸；被压缩时附上比例，
                          // 免得作者以为组件本身就这么小。
                          scale < 1.0
                              ? '${natural.width.toStringAsFixed(0)}×'
                                  '${natural.height.toStringAsFixed(0)}'
                                  '  ·  已缩放至 ${(scale * 100).toStringAsFixed(0)}%'
                              : '${natural.width.toStringAsFixed(0)}×'
                                  '${natural.height.toStringAsFixed(0)}'
                                  '  ·  ${c.children.length} 个元件',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF888896),
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => _exportComposite(c),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.ios_share_rounded,
                          size: 17, color: Color(0xFF00897B)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
