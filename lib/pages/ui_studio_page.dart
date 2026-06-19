import 'package:flutter/material.dart';

import '../services/ui_engine/ui_asset_service.dart';
import '../services/ui_engine/ui_models.dart';
import '../services/ui_engine/ui_renderer.dart';

class UIStudioPage extends StatefulWidget {
  const UIStudioPage({super.key});

  @override
  State<UIStudioPage> createState() => _UIStudioPageState();
}

class _UIStudioPageState extends State<UIStudioPage> {
  final UIAssetService _assetService = UIAssetService();
  
  // 画布上的元素列表
  final List<UIElement> _canvasElements = [];
  // 当前选中的元素 ID
  String? _selectedElementId;
  
  // 面板开关状态
  bool _showAssets = false;
  bool _showProperties = false;

  // 添加组件到画布
  void _addElement(UIModule module) {
    setState(() {
      final newElement = UIElement(
        id: 'el_${DateTime.now().millisecondsSinceEpoch}',
        isComposite: false,
        module: module,
        offset: const Offset(100, 100),
        size: const Size(150, 80),
      );
      _canvasElements.add(newElement);
      _selectedElementId = newElement.id;
      _showAssets = false; // 添加后关闭资产栏
      _showProperties = true; // 自动打开属性栏
    });
  }

  // 更新元素位置
  void _updateElementPosition(String id, Offset newOffset) {
    setState(() {
      final index = _canvasElements.indexWhere((e) => e.id == id);
      if (index != -1) {
        final el = _canvasElements[index];
        _canvasElements[index] = UIElement(
          id: el.id,
          isComposite: el.isComposite,
          module: el.module,
          composite: el.composite,
          offset: newOffset,
          size: el.size,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('UI 创作工作室'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: () {
              // TODO: 实现保存到角色配置的逻辑
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('保存画布布局成功！')),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          // 1. 底层：无限画布 (全屏)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() {
                _selectedElementId = null;
                _showProperties = false;
              }),
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(1000),
                minScale: 0.1,
                maxScale: 3.0,
                child: Stack(
                  children: [
                    // 绘制网格背景 (辅助对齐)
                    Positioned.fill(child: _buildGridBackground()),
                    
                    // 渲染画布元素
                    ..._canvasElements.map((el) => _buildDraggableNode(el)).toList(),
                  ],
                ),
              ),
            ),
          ),
          
          // 2. 左侧：资产库浮窗
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            left: _showAssets ? 0 : -260,
            top: 0,
            bottom: 0,
            width: 250,
            child: _buildAssetPanel(),
          ),
          
          // 3. 右侧：属性面板浮窗
          AnimatedPositioned(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            right: _showProperties ? 0 : -310,
            top: 0,
            bottom: 0,
            width: 300,
            child: _buildPropertiesPanel(),
          ),

          // 底部控制条 (用于快速切换面板)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'asset_btn',
                    onPressed: () => setState(() => _showAssets = !_showAssets),
                    child: Icon(_showAssets ? Icons.close : Icons.grid_view),
                  ),
                  const SizedBox(width: 20),
                  FloatingActionButton.small(
                    heroTag: 'prop_btn',
                    onPressed: () => setState(() => _showProperties = !_showProperties),
                    child: Icon(_showProperties ? Icons.close : Icons.settings),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        borderRadius: const BorderRadius.horizontal(right: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('资产库', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8.0),
              children: [
                _buildAssetTile('原子模组', _assetService.getAllModules()),
                const Divider(),
                _buildAssetTile('组合块', _assetService.getAllComposites()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssetTile(String title, List<dynamic> assets) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
          child: Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        ),
        ...assets.map((asset) {
          final name = (asset is UIModule) ? asset.name : (asset as UIComposite).name;
          return ListTile(
            title: Text(name),
            trailing: const Icon(Icons.add, size: 18),
            onTap: () {
              if (asset is UIModule) {
                _addElement(asset);
              } else if (asset is UIComposite) {
                setState(() {
                  final newEl = UIElement(
                    id: 'comp_${DateTime.now().millisecondsSinceEpoch}',
                    isComposite: true,
                    composite: asset,
                    offset: const Offset(150, 150),
                    size: const Size(300, 200),
                  );
                  _canvasElements.add(newEl);
                  _selectedElementId = newEl.id;
                });
              }
            },
          );
        }).toList(),
      ],
    );
  }

  Widget _buildDraggableNode(UIElement el) {
    bool isSelected = _selectedElementId == el.id;
    return Positioned(
      left: el.offset.dx,
      top: el.offset.dy,
      width: el.size.width,
      height: el.size.height,
      child: GestureDetector(
        onTap: () => setState(() {
          _selectedElementId = el.id;
          _showProperties = true;
        }),
        onPanUpdate: (details) {
          _updateElementPosition(el.id, el.offset + details.delta);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: OverflowBox(
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: UIRenderer.render(context, el),
          ),
        ),
      ),
    );
  }

  Widget _buildGridBackground() {
    return CustomPaint(
      painter: GridPainter(),
      size: Size.infinite,
    );
  }

  Widget _buildPropertiesPanel() {
    if (_selectedElementId == null) {
      return const Center(child: Text('请选择一个元素进行编辑'));
    }

    final el = _canvasElements.firstWhere((e) => e.id == _selectedElementId);
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('属性编辑器', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(),
            const SizedBox(height: 16),
            Text('ID: ${el.id}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(height: 16),
            _buildPropertyField('X 坐标', el.offset.dx),
            _buildPropertyField('Y 坐标', el.offset.dy),
            _buildPropertyField('宽度', el.size.width),
            _buildPropertyField('高度', el.size.height),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedElementId = null;
                  _showProperties = false;
                });
              },
              child: const Text('取消选中'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPropertyField(String label, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          SizedBox(
            width: 80,
            child: Text(value.toStringAsFixed(1), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1.0;

    const double step = 50.0;
    // 绘制一个足够大的网格以适应 InteractiveViewer 的平移
    for (double x = -1000; x < 2000; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = -1000; y < 2000; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
