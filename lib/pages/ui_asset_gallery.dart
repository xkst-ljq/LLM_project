import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/ui_composite_asset_service.dart';
import '../services/ui_engine/linker_service.dart';
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
      if (!mounted) return;
      setState(_registerLinkerBus);
    });
  }

  /// 注册 linker 事件总线。
  ///
  /// **不调用它，卡片里的联动永远不会发生**：LinkerService 靠这个订阅
  /// 接收组件发出的 pulse，再按方案把值算给目标组件，最后调 onStateChanged
  /// 触发重建。运行时视图（UIAssemblyRuntimeView）也是这么做的，
  /// 之前这个页面漏了，所以拖滑块只有滑块自己在动（用户实测）。
  ///
  /// 传入全部复合件的根元素——总线内部会递归收集其中的 linker。
  ///
  /// **资产列表一变就要重新调用**：订阅时传进去的是当时那份快照，
  /// 新导入的组件不在里面，它的 linker 自然收不到 pulse。
  /// 表现就是「导入后必须退出再进来联动才生效」——
  /// 退出会重建 State、重跑 initState，等于被动刷新了一次（用户实测）。
  void _registerLinkerBus() {
    final elements = _assetService.getAllComposites().map((c) {
      return UIElement(
        id: c.id,
        isComposite: true,
        composite: c,
        size: UIRenderer.compositeNaturalSize(c),
      );
    }).toList();
    LinkerService.initEventBusListener(elements, () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    // 解除订阅，避免离开页面后仍持有本 State。
    // 与运行时视图同款写法：传空表 + 空回调即可顶掉旧订阅。
    LinkerService.initEventBusListener(const <UIElement>[], () {});
    super.dispose();
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
    // 设计时的自然尺寸。compositeNaturalSize 取子元素包围盒的右下边界
    // （左上留白也算布局的一部分），正是作者在工作台上看到的尺寸。
    final natural = UIRenderer.compositeNaturalSize(c);

    // **size 必须显式传自然尺寸。**
    //
    // UIElement.size 默认是 100×100，而 _renderComposite 拿它当外框、
    // 再按 `min(外框/自然)` 算一次内部缩放。不传就等于告诉渲染器
    // 「请把 208×93 的内容塞进 100×100」，内容被压到 48%，
    // 外层却仍按自然尺寸撑开，于是卡片下方留出大片空白（用户实测截图）。
    final element = UIElement(
      id: c.id,
      isComposite: true,
      composite: c,
      size: natural,
    );

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
              // 预览区。
              //
              // **这里不能再套 FittedBox**：element.size 已经是自然尺寸，
              // _renderComposite 内部会按 `外框/自然` 再算一次缩放。
              // 外面多包一层等于缩放两次，内容会被压得更小。
              //
              // 需要整体压缩时改用 Transform.scale——它只影响绘制，
              // 不参与布局，因此内部那次缩放的分母不受影响，仍是 1:1。
              SizedBox(
                width: natural.width * scale,
                height: natural.height * scale,
                child: Transform.scale(
                  scale: scale,
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
                  InkWell(
                    onTap: () => _confirmDeleteComposite(c),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(Icons.delete_outline_rounded,
                          size: 18, color: Color(0xFFFF4081)),
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

  /// 删除复合组件。
  ///
  /// 此前只有 UI Studio 能删，而导入入口在本页——
  /// 导错了文件却要跑去另一个页面清理，很别扭（用户反馈）。
  ///
  /// 删除是不可逆的（资产库没有回收站），所以一定要二次确认，
  /// 并在文案里点明「已经用到角色卡里的实例不受影响」——
  /// 否则作者不敢删：复合件在 Assembly 里是**值拷贝**
  /// （UIElement 内嵌完整对象，不按 id 引用资产库），
  /// 删模板不会让已经摆好的界面变空。
  Future<void> _confirmDeleteComposite(UIComposite c) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          '删除资产',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111116),
          ),
        ),
        content: Text(
          '确定从资产库删除「${c.name}」吗？\n\n'
          '已经用到角色卡里的实例不受影响，只是以后不能再从库里取用。',
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF555562),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消',
                style: TextStyle(color: Color(0xFF888896))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4081),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '删除',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // removeComposite 内部已经 saveAssets()。
    _assetService.removeComposite(c.id);
    // 与导入同理：资产列表变了就要重新注册事件总线，
    // 否则总线里还留着已删组件的 linker 快照。
    setState(_registerLinkerBus);
    messenger.showSnackBar(
      SnackBar(content: Text('已删除「${c.name}」')),
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
      // 必须重新注册：事件总线里存的是导入前那份元素快照，
      // 不刷新的话新组件的 linker 永远收不到事件。
      setState(_registerLinkerBus);
      messenger.showSnackBar(
        SnackBar(content: Text('已导入「${composite.name}」')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }
}
