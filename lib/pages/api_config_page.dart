import 'package:flutter/material.dart';

import '../models/api_config.dart';
import '../services/api_config_service.dart';
import '../widgets/page_guide_overlay.dart';
import 'api_config_edit_page.dart';

class ApiConfigPage extends StatefulWidget {
  final bool startGuide;
  final VoidCallback? onExitGuide;

  const ApiConfigPage({
    super.key,
    this.startGuide = false,
    this.onExitGuide,
  });

  @override
  State<ApiConfigPage> createState() => _ApiConfigPageState();
}

class _ApiConfigPageState extends State<ApiConfigPage> {
  List<ApiConfig> _configs = [];
  late bool _showGuide;

  final _addButtonKey = GlobalKey();
  final _emptyHintKey = GlobalKey();
  final _firstConfigTileKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _showGuide = widget.startGuide;
    _loadConfigs();
  }

  Future<void> _loadConfigs() async {
    final configs = await ApiConfigService.getAllConfigs();
    if (!mounted) return;
    setState(() => _configs = configs);
  }

  void _addConfig({bool guided = false}) async {
    final result = await Navigator.push<ApiConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => ApiConfigEditPage(
          startGuide: guided || _showGuide,
          onExitGuide: _exitGuide,
        ),
      ),
    );
    if (result != null) {
      try {
        await ApiConfigService.addConfig(result);
        _loadConfigs();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('保存失败: $e')),
          );
        }
      }
    }
  }

  void _editConfig(ApiConfig config) async {
    final result = await Navigator.push<ApiConfig>(
      context,
      MaterialPageRoute(
        builder: (_) => ApiConfigEditPage(
          config: config,
          startGuide: _showGuide,
          onExitGuide: _exitGuide,
        ),
      ),
    );
    if (result != null) {
      await ApiConfigService.updateConfig(result);
      _loadConfigs();
    }
  }

  void _deleteConfig(ApiConfig config) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除配置“${config.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ApiConfigService.deleteConfig(config.id);
              _loadConfigs();
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _setActive(ApiConfig config) async {
    await ApiConfigService.setActiveConfigId(config.id);
    _loadConfigs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换到 ${config.name}')),
      );
    }
  }

  void _exitGuide() {
    setState(() => _showGuide = false);
    widget.onExitGuide?.call();
  }

  Rect? _rectForKey(GlobalKey key) {
    final keyContext = key.currentContext;
    if (keyContext == null) return null;

    final renderObject = keyContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;

    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }

  Rect _backButtonRect(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Rect.fromLTWH(4, top + 2, 58, kToolbarHeight);
  }

  Rect _fallbackContentRect(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final top = MediaQuery.of(context).padding.top + kToolbarHeight + 24;
    return Rect.fromLTWH(24, top, size.width - 48, 72);
  }

  List<PageGuideTarget> _guideTargets(BuildContext context) {
    final targets = <PageGuideTarget>[
      PageGuideTarget(
        id: 'api_config_back',
        order: 0,
        rect: _backButtonRect(context),
        title: '返回上一页',
        description: '点击这里返回设置页导览。返回只会切换页面，不会关闭教程模式。',
        actionLabel: '返回上一页',
        onAction: () => Navigator.of(context).maybePop(),
        showBadge: false,
      ),
    ];

    final addRect = _rectForKey(_addButtonKey);
    if (addRect != null) {
      targets.add(
        PageGuideTarget(
          id: 'api_config_add',
          order: 1,
          rect: addRect.inflate(4),
          title: '新增 API 配置',
          description: '第一次使用时，通常需要先点击这里新增一个 API 配置。',
          actionLabel: '新增配置',
          onAction: () => _addConfig(guided: true),
        ),
      );
    }

    final listRect = _configs.isEmpty
        ? (_rectForKey(_emptyHintKey) ?? _fallbackContentRect(context))
        : (_rectForKey(_firstConfigTileKey) ?? _fallbackContentRect(context));

    targets.add(
      PageGuideTarget(
        id: 'api_config_list',
        order: 2,
        rect: listRect,
        title: _configs.isEmpty ? '配置列表为空' : 'API 配置列表',
        description: _configs.isEmpty
            ? '这里会显示已经保存的 API 配置。现在还没有配置，建议先点击右上角新增。'
            : '这里会显示所有 API 配置。可以通过每一项右侧菜单设为当前、编辑或删除。',
      ),
    );

    return targets;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Stack(
        children: [
          Scaffold(
            appBar: AppBar(
              title: const Text('API 配置管理'),
              actions: [
                IconButton(
                  key: _addButtonKey,
                  icon: const Icon(Icons.add),
                  onPressed: _addConfig,
                ),
              ],
            ),
            body: _configs.isEmpty
            ? Center(
            child: Container(
            key: _emptyHintKey,
            padding: const EdgeInsets.all(12),
            child: const Text('暂无配置，点击 + 添加'),
            ),
            )
                  : ListView.builder(
                      itemCount: _configs.length,
                      itemBuilder: (ctx, index) {
                        final config = _configs[index];
                        return Container(
                          key: index == 0 ? _firstConfigTileKey : null,
                          child: ListTile(
                            leading: Icon(
                              Icons.api,
                              color: config.apiKey.isNotEmpty ? Colors.blue : Colors.grey,
                            ),
                            title: Text(config.name),
                            subtitle: Text(config.baseUrl),
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'edit') {
                                  _editConfig(config);
                                } else if (value == 'delete') {
                                  _deleteConfig(config);
                                } else if (value == 'activate') {
                                  _setActive(config);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'activate', child: Text('设为当前')),
                                const PopupMenuItem(value: 'edit', child: Text('编辑')),
                                const PopupMenuItem(value: 'delete', child: Text('删除')),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          if (_showGuide)
            Positioned.fill(
              child: PageGuideOverlay(
                title: 'API 配置页导览',
                hint: '点击高光区域执行对应操作；点击紫色编号展开说明。建议先点击“新增 API 配置”。',
                targets: _guideTargets(context),
                onExit: _exitGuide,
              ),
            ),
        ],
      ),
    );
  }
}
