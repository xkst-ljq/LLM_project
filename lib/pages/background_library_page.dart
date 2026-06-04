import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../models/background_card.dart';
import '../services/background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../services/background_asset_service.dart';

class BackgroundImportPreview {
  final File file;
  final String name;
  final String type;
  final String sceneSetting;
  final List<String> checks;

  BackgroundImportPreview({
    required this.file,
    required this.name,
    required this.type,
    required this.sceneSetting,
    required this.checks,
  });
}

class BackgroundLibraryPage extends StatefulWidget {
  const BackgroundLibraryPage({super.key});

  @override
  State<BackgroundLibraryPage> createState() => _BackgroundLibraryPageState();
}

class _BackgroundLibraryPageState extends State<BackgroundLibraryPage> {
  List<BackgroundCard> _backgrounds = [];
  final Set<String> _expandedIds = {};
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadSortPreference();
    _loadBackgrounds();
  }

  Widget _buildSortButton() {
    return GestureDetector(
      onLongPress: () {
        final newAscending = !_sortAscending;
        _updateSort(null, newAscending);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newAscending ? '已切换为正序' : '已切换为倒序'),
            duration: const Duration(milliseconds: 800),
          ),
        );
      },
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.sort),
        tooltip: '排序方式，长按切换正序/倒序',
        onSelected: (value) {
          if (value == 'toggle_order') {
            _updateSort(null, !_sortAscending);
          } else {
            _updateSort(value, null);
          }
        },
        itemBuilder: (context) => [
          CheckedPopupMenuItem(
            value: 'time',
            checked: _sortBy == 'time',
            child: const Text('默认顺序 / 创建时间'),
          ),
          CheckedPopupMenuItem(
            value: 'name',
            checked: _sortBy == 'name',
            child: const Text('按名称排序'),
          ),
          const PopupMenuDivider(),
          PopupMenuItem(
            value: 'toggle_order',
            child: Row(
              children: [
                Icon(
                  _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _sortAscending
                        ? '当前：正序，点击切换倒序'
                        : '当前：倒序，点击切换正序',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateOrImportSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_photo_alternate),
              title: const Text('新建图片背景'),
              onTap: () {
                Navigator.pop(ctx);
                _addBackground();
              },
            ),
            ListTile(
              leading: const Icon(Icons.file_download),
              title: const Text('导入背景卡'),
              subtitle: const Text('导入 LLM Project 图片背景卡'),
              onTap: () {
                Navigator.pop(ctx);
                _importBackgroundCardWithPreview();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<BackgroundImportPreview> _buildBackgroundImportPreview(File file) async {
    final bg = await BackgroundAssetService.readBackgroundAsset(file);

    return BackgroundImportPreview(
      file: file,
      name: bg.name,
      type: bg.type,
      sceneSetting: bg.sceneSetting,
      checks: const [
        '内部识别标识完整',
        '背景卡数据完整',
        '原图数据完整',
      ],
    );
  }

  Future<bool> _showBackgroundImportPreview(
      BackgroundImportPreview preview,
      ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入背景卡'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('类型：${preview.type == 'image' ? '图片背景' : preview.type}'),
              if (preview.sceneSetting.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text(
                  '场景设定：',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  preview.sceneSetting,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              const Text(
                '完整性检查：',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              ...preview.checks.map(
                    (e) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text(e)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认导入'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _exportBackgroundCard(BackgroundCard bg) async {
    try {
      if (bg.type != 'image') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前仅支持导出图片背景卡')),
        );
        return;
      }

      final file = await BackgroundAssetService.exportBackgroundCard(bg);

      final downloadsPath =
      await BackgroundAssetService.saveBackgroundCardToDownloads(file);

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('导出完成'),
          content: Text(
            downloadsPath != null
                ? '背景卡已保存到：\n$downloadsPath'
                : '背景卡已导出到应用目录：\n${file.path}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Share.shareXFiles(
                  [XFile(file.path)],
                  text: 'LLM Project 背景卡',
                );
              },
              child: const Text('分享'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e')),
      );
    }
  }

  void _showBackgroundActions(BackgroundCard bg) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_upload),
              title: const Text('导出背景卡'),
              subtitle: Text(
                bg.type == 'image'
                    ? '以原图比例导出，导入时可自动恢复背景设定'
                    : '当前仅图片背景支持背景卡导出',
              ),
              enabled: bg.type == 'image',
              onTap: bg.type != 'image'
                  ? null
                  : () {
                Navigator.pop(ctx);
                _exportBackgroundCard(bg);
              },
            ),
            if (!bg.isPreset)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  '删除背景',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteBackground(bg);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _importBackgroundCardWithPreview() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择 LLM Project 背景卡文件',
      type: FileType.any,
      allowMultiple: false,
    );

    if (picked == null || picked.files.isEmpty) return;

    final path = picked.files.single.path;
    if (path == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取该文件')),
      );
      return;
    }

    final file = File(path);
    late BackgroundImportPreview preview;

    try {
      preview = await _buildBackgroundImportPreview(file);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '读取失败：$e\n'
                '请选择由 LLM Project 导出的背景卡文件。'
                '如果这是聊天软件转发的图片，请确认对方发送的是原图或完整文件。',
          ),
        ),
      );
      return;
    }

    if (!mounted) return;

    final confirmed = await _showBackgroundImportPreview(preview);
    if (!confirmed) return;

    try {
      await BackgroundAssetService.importBackgroundCard(file);
      await _loadBackgrounds();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('背景卡导入成功')),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败：$e')),
      );
    }
  }

  Future<void> _loadSortPreference() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _sortBy = prefs.getString(_sortByKey) ?? 'time';
      _sortAscending = prefs.getBool(_sortAscendingKey) ?? true;
    });
  }

  Future<void> _updateSort(String? sortBy, bool? ascending) async {
    final prefs = await SharedPreferences.getInstance();
    if (sortBy != null) {
      _sortBy = sortBy;
      await prefs.setString(_sortByKey, sortBy);
    }
    if (ascending != null) {
      _sortAscending = ascending;
      await prefs.setBool(_sortAscendingKey, ascending);
    }
    setState(() {
      _sortBackgrounds();
    });
  }

  void _openBackgroundEdit(BackgroundCard bg, int index) {
    final col = index % 2;
    final row = index ~/ 2;
    const cardWidth = 160.0;
    const cardHeight = 240.0;
    const crossSpacing = 12.0;
    const mainSpacing = 12.0;
    const padding = 16.0;

    final cardLeft = padding + col * (cardWidth + crossSpacing);
    final cardTop =
        kToolbarHeight +
            MediaQuery.of(context).padding.top +
            padding +
            row * (cardHeight + mainSpacing);

    Navigator.of(context)
        .push(
      _BackgroundEditRoute(
        background: bg,
        cardRect: Rect.fromLTWH(cardLeft, cardTop, cardWidth, cardHeight),
      ),
    )
        .then((_) => _loadBackgrounds());
  }

  Future<void> _loadBackgrounds() async {
    final all = await BackgroundService.getAll();
    setState(() => _backgrounds = all);
    _sortBackgrounds();
  }

  Future<void> _addBackground() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final dir = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final originalPath = p.join(dir.path, 'bg_original_$id.png');
    await File(picked.path).copy(originalPath);

    final bg = BackgroundCard(
      id: id,
      name: '自定义背景 ${_backgrounds.length + 1}',
      type: 'image',
      originalImagePath: originalPath,
      isPreset: false,
    );
    await BackgroundService.insert(bg);
    _loadBackgrounds();
  }

  void _deleteBackground(BackgroundCard bg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除背景“${bg.name}”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await BackgroundService.delete(bg.id);
              _loadBackgrounds();
              _expandedIds.remove(bg.id);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
  String _sortBy = 'time'; // 默认按创建时间
  bool _sortAscending = true;
  static const String _sortByKey = 'background_sort_by';
  static const String _sortAscendingKey = 'background_sort_ascending';

  int _createdTimeOf(String id) {
    return int.tryParse(id) ?? 0;
  }

  int _compareBackgroundByTime(BackgroundCard a, BackgroundCard b) {
    final at = _createdTimeOf(a.id);
    final bt = _createdTimeOf(b.id);

    if (at != bt) {
      return _sortAscending ? at.compareTo(bt) : bt.compareTo(at);
    }

    final nameCompare = a.name.compareTo(b.name);
    if (nameCompare != 0) {
      return _sortAscending ? nameCompare : -nameCompare;
    }

    return a.id.compareTo(b.id);
  }

  int _compareBackgroundByName(BackgroundCard a, BackgroundCard b) {
    final nameCompare = a.name.trim().compareTo(b.name.trim());

    if (nameCompare != 0) {
      return _sortAscending ? nameCompare : -nameCompare;
    }

    return _compareBackgroundByTime(a, b);
  }

  void _sortBackgrounds() {
    if (_sortBy == 'name') {
      _backgrounds.sort(_compareBackgroundByName);
    } else {
      _backgrounds.sort(_compareBackgroundByTime);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('背景图库'),
        actions: [
          _buildSortButton(),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '新建或导入',
            onPressed: _showCreateOrImportSheet,
          ),
        ],
      ),
      body: _backgrounds.isEmpty
          ? const Center(child: Text('暂无背景，点击 + 添加'))
          : GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2 / 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _backgrounds.length,
        itemBuilder: (context, index) {
          final bg = _backgrounds[index];
          final isExpanded = _expandedIds.contains(bg.id);

          return GestureDetector(
            onTap: () {
              if (isExpanded) {
                _expandedIds.remove(bg.id);
                _openBackgroundEdit(bg, index);
              } else {
                setState(() {
                  _expandedIds.clear();
                  _expandedIds.add(bg.id);
                });
              }
            },
            onLongPress: () => _showBackgroundActions(bg),
            child: AspectRatio(
              aspectRatio: 2 / 3,
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: _buildPreview(bg),
                  ),
                  if (isExpanded)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                        ),
                        child: Text(
                          bg.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreview(BackgroundCard bg) {
    switch (bg.type) {
      case 'color':
        try {
          final data = jsonDecode(bg.colorValue.isEmpty ? '{}' : bg.colorValue);
          final active = data['active'] as String?;
          if (active == 'color' && data.containsKey('color')) {
            final hex = data['color'] as String;
            return Container(
              color: Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16)),
            );
          }
        } catch (_) {}
        return Container(color: Colors.grey[300]);
      case 'gradient':
        try {
          final data = jsonDecode(bg.colorValue.isEmpty ? '{}' : bg.colorValue);
          final gradientList = data['gradient'] as List?;
          if (gradientList != null && gradientList.isNotEmpty) {
            final colors = <Color>[];
            final stops = <double>[];
            for (final item in gradientList) {
              final hex = item['color'] as String?;
              if (hex != null) {
                colors.add(
                  Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16)),
                );
                stops.add((item['position'] as num?)?.toDouble() ?? 0.0);
              }
            }
            if (colors.isNotEmpty) {
              final first = gradientList.first as Map<String, dynamic>;
              final sx = (first['startX'] as num?)?.toDouble() ?? 0.5;
              final sy = (first['startY'] as num?)?.toDouble() ?? 0.0;
              final ex = (first['endX'] as num?)?.toDouble() ?? 0.5;
              final ey = (first['endY'] as num?)?.toDouble() ?? 1.0;

              return Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    begin: Alignment(sx * 2 - 1, sy * 2 - 1),
                    end: Alignment(ex * 2 - 1, ey * 2 - 1),
                    colors: colors,
                    stops: stops,
                  ),
                ),
              );
            }
          }
        } catch (_) {}
        return Container(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFE3F2FD), Color(0xFFF3E5F5)],
            ),
          ),
        );
      case 'image':
        if (bg.originalImagePath.isNotEmpty) {
          final file = File(bg.originalImagePath);
          if (file.existsSync()) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                file,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            );
          }
        }
        return Container(color: Colors.grey[300]);
      default:
        return Container(color: Colors.grey[300]);
    }
  }
}

class _BackgroundEditRoute extends PageRouteBuilder {
  _BackgroundEditRoute({required this.background, required this.cardRect})
      : super(
    pageBuilder: (context, animation, secondaryAnimation) {
      return _BackgroundEditContent(
        background: background,
        cardRect: cardRect,
      );
    },
    transitionDuration: const Duration(milliseconds: 350),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    opaque: false,
    barrierDismissible: true,
    barrierColor: Colors.black54,
    barrierLabel: '关闭',
  );

  final BackgroundCard background;
  final Rect cardRect;

  @override
  Widget buildTransitions(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class _BackgroundEditContent extends StatefulWidget {
  final BackgroundCard background;
  final Rect cardRect;

  const _BackgroundEditContent({
    required this.background,
    required this.cardRect,
  });

  @override
  State<_BackgroundEditContent> createState() => _BackgroundEditContentState();
}

class _BackgroundEditContentState extends State<_BackgroundEditContent>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  Animation<Rect?>? _rectAnimation;
  Color _pickedColor = Colors.blue;
  final List<Color> _presetColors = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
    Colors.blueGrey,
    Colors.white,
    Colors.black,
    const Color(0xFFFFF3E0),
    const Color(0xFFFFE0B2),
    const Color(0xFFFFCC80),
    const Color(0xFFE8F5E9),
    const Color(0xFFB2DFDB),
    const Color(0xFF80CBC4),
    const Color(0xFFE3F2FD),
    const Color(0xFFBBDEFB),
    const Color(0xFF90CAF9),
    const Color(0xFFF3E5F5),
    const Color(0xFFE1BEE7),
    const Color(0xFFCE93D8),
    const Color(0xFFF9FBE7),
    const Color(0xFFF0F4C3),
    const Color(0xFFE6EE9C),
  ];
  String? _uploadOriginalPath;
  String? _uploadPortraitPath;
  String? _uploadLandscapePath;
  final ImagePicker _picker = ImagePicker();
  final List<Color> _recentColors = [];
  String _gradientSubTab = 'color1';
  List<GradientStop> _gradientStops = [];
  int _gradientSelectedStopIndex = 0;
  Offset? _startFingerOffset;
  Offset? _endFingerOffset;

  void _addGradientStop(Color color, double position) {
    _gradientStops.add(GradientStop(color: color, position: position));
  }

  void _initGradientStops() {
    if (_gradientStops.isEmpty) {
      _gradientStops = [
        GradientStop(color: Colors.red, position: 0.0),
        GradientStop(color: Colors.blue, position: 1.0),
      ];
      _gradientSelectedStopIndex = 0;
      _gradientSubTab = 'color_0';
    }
  }

  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  bool _editingName = false;
  bool _editingDesc = false;
  bool _showNameError = false;
  String _nameErrorText = '';

  void _addRecentColor(Color color) {
    _recentColors.removeWhere((c) => c.toARGB32() == color.toARGB32());
    _recentColors.insert(0, color);
    if (_recentColors.length > 4) {
      _recentColors.removeRange(4, _recentColors.length);
    }
  }

  Widget _buildColorSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            activeColor: _pickedColor,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildGradientPreview() {
    if (_gradientStops.isEmpty) return const Center(child: Text('无颜色点'));
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = width * 1.5;
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: CustomPaint(
              painter: _GradientPreviewPainter(stops: _gradientStops),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradientContent() {
    if (_gradientSubTab == 'preview') return _buildGradientPreview();

    final stop = _gradientStops[_gradientSelectedStopIndex];
    final Color currentColor = stop.color;

    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: double.infinity,
                      height: 36,
                      decoration: BoxDecoration(
                        color: currentColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildColorSlider(
                      label: '色相',
                      value: HSVColor.fromColor(currentColor).hue,
                      min: 0,
                      max: 360,
                      divisions: 360,
                      onChanged: (v) {
                        setState(() {
                          final hsv = HSVColor.fromColor(currentColor);
                          stop.color = hsv.withHue(v).toColor();
                        });
                      },
                    ),
                    _buildColorSlider(
                      label: '饱和度',
                      value: HSVColor.fromColor(currentColor).saturation,
                      min: 0,
                      max: 1,
                      divisions: 100,
                      onChanged: (v) {
                        setState(() {
                          final hsv = HSVColor.fromColor(currentColor);
                          stop.color = hsv.withSaturation(v).toColor();
                        });
                      },
                    ),
                    _buildColorSlider(
                      label: '明度',
                      value: HSVColor.fromColor(currentColor).value,
                      min: 0,
                      max: 1,
                      divisions: 100,
                      onChanged: (v) {
                        setState(() {
                          final hsv = HSVColor.fromColor(currentColor);
                          stop.color = hsv.withValue(v).toColor();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemCount: _presetColors.length,
                      itemBuilder: (context, index) {
                        final c = _presetColors[index];
                        final isSelected =
                            c.toARGB32() == currentColor.toARGB32();
                        return GestureDetector(
                          onTap: () => setState(() => stop.color = c),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c,
                              borderRadius: BorderRadius.circular(4),
                              border: isSelected
                                  ? Border.all(color: Colors.white, width: 2)
                                  : null,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final boxWidth = constraints.maxWidth;
                  final boxHeight = boxWidth * 1.5;
                  const circleSize = 22.0;

                  final stop = _gradientStops[_gradientSelectedStopIndex];
                  final type = stop.type;

                  double startLeft =
                      stop.startX * (boxWidth - circleSize);
                  double startTop =
                      stop.startY * (boxHeight - circleSize);
                  double endLeft =
                      stop.endX * (boxWidth - circleSize);
                  double endTop =
                      stop.endY * (boxHeight - circleSize);

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ClipRect(
                        child: Container(
                          width: boxWidth,
                          height: boxHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CustomPaint(
                                painter: type == 'linear'
                                    ? _SingleStopLinePainter(
                                  start: Offset(
                                    startLeft + circleSize / 2,
                                    startTop + circleSize / 2,
                                  ),
                                  end: Offset(
                                    endLeft + circleSize / 2,
                                    endTop + circleSize / 2,
                                  ),
                                )
                                    : _SingleStopRadialPainter(
                                  center: Offset(
                                    startLeft + circleSize / 2,
                                    startTop + circleSize / 2,
                                  ),
                                  radius:
                                  (Offset(
                                    endLeft + circleSize / 2,
                                    endTop + circleSize / 2,
                                  ) -
                                      Offset(
                                        startLeft +
                                            circleSize / 2,
                                        startTop + circleSize / 2,
                                      ))
                                      .distance,
                                ),
                                size: Size(boxWidth, boxHeight),
                              ),
                              Positioned(
                                left: startLeft,
                                top: startTop,
                                child: GestureDetector(
                                  onPanStart: (details) {
                                    _startFingerOffset = Offset(
                                      startLeft +
                                          circleSize / 2 -
                                          details.localPosition.dx,
                                      startTop +
                                          circleSize / 2 -
                                          details.localPosition.dy,
                                    );
                                  },
                                  onPanUpdate: (details) {
                                    final fingerX =
                                        details.localPosition.dx +
                                            (_startFingerOffset?.dx ?? 0);
                                    final fingerY =
                                        details.localPosition.dy +
                                            (_startFingerOffset?.dy ?? 0);
                                    final newLeft = (fingerX - circleSize / 2)
                                        .clamp(0.0, boxWidth - circleSize);
                                    final newTop = (fingerY - circleSize / 2)
                                        .clamp(0.0, boxHeight - circleSize);
                                    setState(() {
                                      stop.startX =
                                          newLeft / (boxWidth - circleSize);
                                      stop.startY =
                                          newTop / (boxHeight - circleSize);
                                    });
                                  },
                                  onPanEnd: (_) => _startFingerOffset = null,
                                  child: Container(
                                    width: circleSize,
                                    height: circleSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(
                                        0xFF4CAF50,
                                      ).withAlpha(230),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        type == 'radial' ? 'C' : 'S',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                left: endLeft,
                                top: endTop,
                                child: GestureDetector(
                                  onPanStart: (details) {
                                    _endFingerOffset = Offset(
                                      endLeft +
                                          circleSize / 2 -
                                          details.localPosition.dx,
                                      endTop +
                                          circleSize / 2 -
                                          details.localPosition.dy,
                                    );
                                  },
                                  onPanUpdate: (details) {
                                    final fingerX =
                                        details.localPosition.dx +
                                            (_endFingerOffset?.dx ?? 0);
                                    final fingerY =
                                        details.localPosition.dy +
                                            (_endFingerOffset?.dy ?? 0);
                                    if (type == 'radial') {
                                      final fingerCenterX =
                                          fingerX - circleSize / 2;
                                      final fingerCenterY =
                                          fingerY - circleSize / 2;
                                      final clampedEndX = fingerCenterX.clamp(
                                        0.0,
                                        boxWidth - circleSize,
                                      );
                                      final clampedEndY = fingerCenterY.clamp(
                                        0.0,
                                        boxHeight - circleSize,
                                      );
                                      setState(() {
                                        stop.endX =
                                            clampedEndX /
                                                (boxWidth - circleSize);
                                        stop.endY =
                                            clampedEndY /
                                                (boxHeight - circleSize);
                                      });
                                    } else {
                                      final newLeft = (fingerX - circleSize / 2)
                                          .clamp(0.0, boxWidth - circleSize);
                                      final newTop = (fingerY - circleSize / 2)
                                          .clamp(0.0, boxHeight - circleSize);
                                      setState(() {
                                        stop.endX =
                                            newLeft / (boxWidth - circleSize);
                                        stop.endY =
                                            newTop / (boxHeight - circleSize);
                                      });
                                    }
                                  },
                                  onPanEnd: (_) => _endFingerOffset = null,
                                  child: Container(
                                    width: circleSize,
                                    height: circleSize,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: const Color(
                                        0xFFF44336,
                                      ).withAlpha(230),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: const [
                                        BoxShadow(
                                          color: Colors.black26,
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Center(
                                      child: Text(
                                        type == 'radial' ? 'R' : 'E',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('线', style: TextStyle(fontSize: 12)),
                          Switch(
                            value: type == 'radial',
                            onChanged: (val) {
                              setState(() {
                                stop.type = val ? 'radial' : 'linear';
                              });
                            },
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          const Text('点', style: TextStyle(fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _savePresetColor() async {
    final hex =
        '#${_pickedColor.toARGB32().toRadixString(16).substring(2).padLeft(6, '0')}';
    final recentHexList = _recentColors
        .map((c) => '#${c.toARGB32().toRadixString(16).substring(2).padLeft(6, '0')}')
        .toList();

    String colorValue;
    try {
      final existing = jsonDecode(widget.background.colorValue.isEmpty
          ? '{}'
          : widget.background.colorValue);
      existing['active'] = 'color';
      existing['color'] = hex;
      existing['recent'] = recentHexList;
      colorValue = jsonEncode(existing);
    } catch (_) {
      colorValue = jsonEncode({
        'active': 'color',
        'color': hex,
        'recent': recentHexList,
      });
    }
    widget.background.type = 'color';
    widget.background.colorValue = colorValue;
    await BackgroundService.update(widget.background);
    final current = await BackgroundService.getCurrent();
    if (current?.id == widget.background.id) {
      await BackgroundService.setCurrent(widget.background.id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('背景已更新')),
      );
      Navigator.pop(context);
    }
  }

  void _savePresetGradient() async {
    final gradientList = _gradientStops.map((s) => s.toJson()).toList();

    String colorValue;
    try {
      final existing = jsonDecode(widget.background.colorValue.isEmpty
          ? '{}'
          : widget.background.colorValue);
      existing['active'] = 'gradient';
      existing['gradient'] = gradientList;
      colorValue = jsonEncode(existing);
    } catch (_) {
      colorValue = jsonEncode({
        'active': 'gradient',
        'gradient': gradientList,
      });
    }

    widget.background.type = 'gradient';
    widget.background.colorValue = colorValue;
    await BackgroundService.update(widget.background);

    final current = await BackgroundService.getCurrent();
    if (current?.id == widget.background.id) {
      await BackgroundService.setCurrent(widget.background.id);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('背景已更新')),
      );
      Navigator.pop(context);
    }
  }

  void _savePresetImage() async {
    if (_uploadOriginalPath == null) return;
    String colorValue;
    try {
      final existing = jsonDecode(widget.background.colorValue.isEmpty
          ? '{}'
          : widget.background.colorValue);
      existing['active'] = 'upload';
      existing['upload'] = {
        'original': _uploadOriginalPath,
        'portrait': _uploadPortraitPath ?? '',
        'landscape': _uploadLandscapePath ?? '',
      };
      colorValue = jsonEncode(existing);
    } catch (_) {
      colorValue = jsonEncode({
        'active': 'upload',
        'upload': {
          'original': _uploadOriginalPath,
          'portrait': _uploadPortraitPath ?? '',
          'landscape': _uploadLandscapePath ?? '',
        },
      });
    }
    widget.background.type = 'image';
    widget.background.originalImagePath = _uploadOriginalPath!;
    widget.background.colorValue = colorValue;
    await BackgroundService.update(widget.background);
    final current = await BackgroundService.getCurrent();
    if (current?.id == widget.background.id) {
      await BackgroundService.setCurrent(widget.background.id);
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('背景已更新')),
      );
      Navigator.pop(context);
    }
  }

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _nameCtrl = TextEditingController(text: widget.background.name);
    _descCtrl = TextEditingController(text: widget.background.sceneSetting);

    if (widget.background.isPreset) {
      try {
        final data = jsonDecode(
          widget.background.colorValue.isEmpty
              ? '{}'
              : widget.background.colorValue,
        );
        _activeTab = data['active'] as String? ?? 'gradient';
        // 恢复纯色数据
        if (data.containsKey('color')) {
          final hex = data['color'] as String;
          _pickedColor = Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16));
          _recentColors.clear();
          _recentColors.add(_pickedColor);
          if (data.containsKey('recent')) {
            final recentList = data['recent'] as List;
            for (final hexStr in recentList) {
              if (hexStr is String && hexStr.startsWith('#')) {
                final color = Color(int.parse(hexStr.replaceFirst('#', 'FF'), radix: 16));
                if (!_recentColors.any((c) => c.toARGB32() == color.toARGB32())) {
                  _recentColors.add(color);
                }
              }
            }
          }
        }
        // 恢复渐变数据
        if (data.containsKey('gradient')) {
          final gradientList = data['gradient'] as List;
          _gradientStops = gradientList
              .map((item) => GradientStop.fromJson(item as Map<String, dynamic>))
              .toList();
        }
        // 恢复上传数据
        if (data.containsKey('upload')) {
          final uploadData = data['upload'] as Map<String, dynamic>;
          _uploadOriginalPath = uploadData['original'] as String?;
          _uploadPortraitPath = uploadData['portrait'] as String?;
          _uploadLandscapePath = uploadData['landscape'] as String?;
        }
      } catch (_) {}
    }
    _initGradientStops();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rectAnimation != null) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final targetWidth = screenWidth * 0.9;
    final targetHeight = screenHeight * 0.7;
    final targetRect = Rect.fromCenter(
      center: Offset(screenWidth / 2, screenHeight / 2),
      width: targetWidth,
      height: targetHeight,
    );
    _rectAnimation = RectTween(begin: widget.cardRect, end: targetRect).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newName = _nameCtrl.text.trim();

    // 重名检查
    final all = await BackgroundService.getAll();
    final existingNames = all
        .where((b) => b.id != widget.background.id)
        .map((b) => b.name)
        .toSet();
    if (existingNames.contains(newName)) {
      setState(() {
        _nameErrorText = '背景名称"$newName"已存在，请换一个名字。';
        _showNameError = true;
      });
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) setState(() => _showNameError = false);
      });
      return;
    }
    widget.background.name = _nameCtrl.text.trim();
    widget.background.sceneSetting = _descCtrl.text.trim();
    await BackgroundService.update(widget.background);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已保存')),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _uploadImage() async {
    final XFile? picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final id = DateTime.now().millisecondsSinceEpoch.toString();
    final originalPath = p.join(dir.path, 'preset_original_$id.png');
    await File(picked.path).copy(originalPath);
    setState(() {
      _uploadOriginalPath = originalPath;
      _uploadPortraitPath = null;
      _uploadLandscapePath = null;
    });
  }

  void _clearUpload() {
    setState(() {
      _uploadOriginalPath = null;
      _uploadPortraitPath = null;
      _uploadLandscapePath = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_rectAnimation == null) return const SizedBox.shrink();
    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const SizedBox.expand(),
        ),
        AnimatedBuilder(
          animation: _rectAnimation!,
          builder: (context, child) {
            final rect = _rectAnimation!.value!;
            return Positioned(
              left: rect.left,
              top: rect.top,
              width: rect.width,
              height: rect.height,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Material(
                  elevation: 16,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    padding: EdgeInsets.zero,
                    child: widget.background.isPreset
                        ? _buildPresetEditor()
                        : _buildCustomEditor(),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _activeTab = 'gradient';

  Widget _buildPresetEditor() {
    return Row(
      children: [
        Expanded(child: _buildPresetContent()),
        SizedBox(
          width: 50,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _buildTab('纯色', 'color', isFirst: true),
              _buildTab('渐变', 'gradient'),
              _buildTab('上传', 'upload'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String label, String key, {bool isFirst = false}) {
    final isActive = _activeTab == key;
    return GestureDetector(
      onTap: () => setState(() => _activeTab = key),
      child: Container(
        width: 50,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        decoration: BoxDecoration(
          color: isActive ? Colors.transparent : Colors.grey.shade200,
          borderRadius: isFirst && !isActive
              ? const BorderRadius.only(topRight: Radius.circular(8))
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Theme.of(context).primaryColor : Colors.grey,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPresetContent() {
    switch (_activeTab) {
      case 'color':
        return Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 60),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_recentColors.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: SizedBox(
                          height: 48,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _recentColors.map((color) {
                              final isSelected =
                                  color.toARGB32() == _pickedColor.toARGB32();
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _pickedColor = color),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: isSelected
                                          ? Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      )
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 16,
                                    )
                                        : null,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () {
                          _addRecentColor(_pickedColor);
                          setState(() {});
                        },
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('保存颜色'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        color: Colors.grey.shade200,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: double.infinity,
                              height: 40,
                              decoration: BoxDecoration(
                                color: _pickedColor,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildColorSlider(
                              label: '色相',
                              value: HSVColor.fromColor(_pickedColor).hue,
                              min: 0,
                              max: 360,
                              divisions: 360,
                              onChanged: (v) {
                                setState(() {
                                  final hsv = HSVColor.fromColor(_pickedColor);
                                  _pickedColor = hsv.withHue(v).toColor();
                                });
                              },
                            ),
                            _buildColorSlider(
                              label: '饱和度',
                              value: HSVColor.fromColor(
                                _pickedColor,
                              ).saturation,
                              min: 0,
                              max: 1,
                              divisions: 100,
                              onChanged: (v) {
                                setState(() {
                                  final hsv = HSVColor.fromColor(_pickedColor);
                                  _pickedColor = hsv
                                      .withSaturation(v)
                                      .toColor();
                                });
                              },
                            ),
                            _buildColorSlider(
                              label: '明度',
                              value: HSVColor.fromColor(_pickedColor).value,
                              min: 0,
                              max: 1,
                              divisions: 100,
                              onChanged: (v) {
                                setState(() {
                                  final hsv = HSVColor.fromColor(_pickedColor);
                                  _pickedColor = hsv.withValue(v).toColor();
                                });
                              },
                            ),
                            const SizedBox(height: 8),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 8,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 4,
                              ),
                              itemCount: _presetColors.length,
                              itemBuilder: (context, index) {
                                final color = _presetColors[index];
                                final isSelected =
                                    color.toARGB32() == _pickedColor.toARGB32();
                                return GestureDetector(
                                  onTap: () =>
                                      setState(() => _pickedColor = color),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: color,
                                      borderRadius: BorderRadius.circular(4),
                                      border: isSelected
                                          ? Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      )
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 14,
                                    )
                                        : null,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: FilledButton(
                onPressed: () {
                  final isFromRecent = _recentColors.any(
                        (c) => c.toARGB32() == _pickedColor.toARGB32(),
                  );
                  if (_recentColors.isEmpty || !isFromRecent) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('请先在记录块中选择一个颜色'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                  _savePresetColor();
                },
                child: const Text('应用背景'),
              ),
            ),
          ],
        );
      case 'gradient':
        return Stack(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Flexible(
                        child: ClipRRect(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(20),
                            right: Radius.circular(20),
                          ),
                          child: Container(
                            height: 40,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(20),
                                right: Radius.circular(20),
                              ),
                            ),
                            child: ListView.builder(
                              shrinkWrap: true,
                              scrollDirection: Axis.horizontal,
                              itemCount: _gradientStops.length,
                              itemBuilder: (context, index) {
                                final isLast =
                                    index == _gradientStops.length - 1;
                                final showAdd =
                                    isLast && _gradientStops.length < 10;
                                final isActive =
                                    _gradientSelectedStopIndex == index &&
                                        _gradientSubTab != 'preview';
                                final color = _gradientStops[index].color;

                                if (showAdd) {
                                  return SizedBox(
                                    width: 60,
                                    height: 40,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Positioned(
                                          left: 0,
                                          top: 2,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              setState(() {
                                                _addGradientStop(Colors.white, 0.5);
                                                _gradientSelectedStopIndex =
                                                    _gradientStops.length - 1;
                                                _gradientSubTab =
                                                'color_$_gradientSelectedStopIndex';
                                              });
                                            },
                                            child: Container(
                                              width: 60,
                                              height: 36,
                                              decoration: const BoxDecoration(
                                                color: Color(0xFFE0E0E0),
                                                borderRadius:
                                                BorderRadius.horizontal(
                                                  left: Radius.circular(18),
                                                  right: Radius.circular(
                                                    18,
                                                  ),
                                                ),
                                              ),
                                              child: const Align(
                                                alignment:
                                                Alignment.centerRight,
                                                child: Padding(
                                                  padding: EdgeInsets.only(
                                                    right: 12,
                                                  ),
                                                  child: Icon(
                                                    Icons.add,
                                                    size: 16,
                                                    color: Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Positioned(
                                          left: 0,
                                          top: 2,
                                          child: GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              setState(() {
                                                _gradientSelectedStopIndex =
                                                    index;
                                                _gradientSubTab =
                                                'color_$index';
                                              });
                                            },
                                            onLongPress: () {
                                              if (_gradientStops.length <= 2) {
                                                return;
                                              }
                                              setState(() {
                                                _gradientStops.removeAt(index);
                                                if (_gradientSelectedStopIndex >=
                                                    _gradientStops.length) {
                                                  _gradientSelectedStopIndex =
                                                      _gradientStops.length - 1;
                                                }
                                                _gradientSubTab =
                                                'color_$_gradientSelectedStopIndex';
                                              });
                                            },
                                            child: Container(
                                              width: 36,
                                              height: 36,
                                              decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                                border: isActive
                                                    ? Border.all(
                                                  color: Colors.white,
                                                  width: 2,
                                                )
                                                    : Border.all(
                                                  color: Colors
                                                      .grey
                                                      .shade400,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }

                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    setState(() {
                                      _gradientSelectedStopIndex = index;
                                      _gradientSubTab = 'color_$index';
                                    });
                                  },
                                  onLongPress: () {
                                    if (_gradientStops.length <= 2) return;
                                    setState(() {
                                      _gradientStops.removeAt(index);
                                      if (_gradientSelectedStopIndex >=
                                          _gradientStops.length) {
                                        _gradientSelectedStopIndex =
                                            _gradientStops.length - 1;
                                      }
                                      _gradientSubTab =
                                      'color_$_gradientSelectedStopIndex';
                                    });
                                  },
                                  child: Container(
                                    width: 36,
                                    height: 36,
                                    margin: const EdgeInsets.only(
                                      left: 4,
                                      top: 2,
                                      bottom: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: isActive
                                          ? Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      )
                                          : Border.all(
                                        color: Colors.grey.shade400,
                                        width: 1,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              setState(() => _gradientSubTab = 'preview'),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _gradientSubTab == 'preview'
                                  ? Theme.of(context).scaffoldBackgroundColor
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(8),
                              border: _gradientSubTab == 'preview'
                                  ? Border.all(color: Colors.grey.shade300)
                                  : null,
                            ),
                            child: Text(
                              '预览',
                              style: TextStyle(
                                fontSize: 11,
                                color: _gradientSubTab == 'preview'
                                    ? Theme.of(context).primaryColor
                                    : Colors.black54,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(20),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _buildGradientContent(),
                    ),
                  ),
                ),
              ],
            ),
            if (_gradientSubTab != 'preview')
              Positioned(
                bottom: 8,
                right: 8,
                child: FilledButton(
                  onPressed: _savePresetGradient,
                  child: const Text('应用背景'),
                ),
              ),
          ],
        );
      case 'upload':
        return Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_uploadOriginalPath != null) ...[
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final maxHeight = constraints.maxHeight - 48; // 给下方按钮留空间
                                return Center(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: maxHeight.clamp(200.0, 400.0),
                                      child: Image.file(
                                        File(_uploadOriginalPath!),
                                        fit: BoxFit.contain,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: _clearUpload,
                                  icon: const Icon(Icons.delete, size: 16),
                                  label: const Text('清除'),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton.icon(
                                  onPressed: _uploadImage,
                                  icon: const Icon(Icons.refresh, size: 16),
                                  label: const Text('更换图片'),
                                ),
                              ],
                            ),
                          ] else ...[
                            Center(
                              child: Column(
                                children: [
                                  Icon(
                                    Icons.cloud_upload,
                                    size: 64,
                                    color: Colors.grey.shade400,
                                  ),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(

                                    onPressed: _uploadImage,
                                    icon: const Icon(Icons.image),
                                    label: const Text('从相册选择图片'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              bottom: 8,
              right: 8,
              child: FilledButton(
                onPressed: _uploadOriginalPath != null ? _savePresetImage : null,
                child: const Text('应用背景'),
              ),
            ),
          ],
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildCustomEditor() {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 60),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '背景名称',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    if (_showNameError)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withAlpha(25),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            _nameErrorText,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _editingName = !_editingName),
                      child: Icon(
                        _editingName ? Icons.check : Icons.edit,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _editingName
                    ? TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                )
                    : Center(
                  child: Text(
                    _nameCtrl.text.isEmpty ? '未命名' : _nameCtrl.text,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text(
                      '场景设定',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() => _editingDesc = !_editingDesc),
                      child: Icon(
                        _editingDesc ? Icons.check : Icons.edit,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _editingDesc
                    ? TextField(
                  controller: _descCtrl,
                  autofocus: true,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                )
                    : Center(
                  child: Text(
                    _descCtrl.text.isEmpty ? '暂无场景设定' : _descCtrl.text,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 16),
                if (widget.background.originalImagePath.isNotEmpty) ...[
                  const Text(
                    '原图预览',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: double.infinity,
                      height: 200,
                      child: Image.file(
                        File(widget.background.originalImagePath),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          right: 12,
          child: FilledButton(onPressed: _save, child: const Text('保存')),
        ),
      ],
    );
  }
}

class _SingleStopLinePainter extends CustomPainter {
  final Offset start;
  final Offset end;

  _SingleStopLinePainter({required this.start, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(start, end, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _SingleStopRadialPainter extends CustomPainter {
  final Offset center;
  final double radius;

  _SingleStopRadialPainter({required this.center, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final paint = Paint()
      ..color = Colors.grey.shade400
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class _GradientPreviewPainter extends CustomPainter {
  final List<GradientStop> stops;

  _GradientPreviewPainter({required this.stops});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stop in stops) {
      final type = stop.type;
      final color = stop.color;
      final startX = stop.startX;
      final startY = stop.startY;
      final endX = stop.endX;
      final endY = stop.endY;

      final rect = Offset.zero & size;
      final transparentColor = color.withAlpha(0);

      if (type == 'radial') {
        final dx = (endX - startX) * size.width;
        final dy = (endY - startY) * size.height;
        final radius = sqrt(dx * dx + dy * dy);
        final shader = RadialGradient(
          center: Alignment(startX * 2 - 1, startY * 2 - 1),
          radius: radius / size.width,
          colors: [color, transparentColor],
          stops: const [0.0, 1.0],
        ).createShader(rect);
        canvas.drawRect(rect, Paint()..shader = shader);
      } else {
        final shader = LinearGradient(
          begin: Alignment(startX * 2 - 1, startY * 2 - 1),
          end: Alignment(endX * 2 - 1, endY * 2 - 1),
          colors: [color, transparentColor],
          stops: const [0.0, 1.0],
        ).createShader(rect);
        canvas.drawRect(rect, Paint()..shader = shader);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GradientPreviewPainter oldDelegate) {
    if (oldDelegate.stops.length != stops.length) return true;
    for (int i = 0; i < stops.length; i++) {
      if (oldDelegate.stops[i].color != stops[i].color ||
          oldDelegate.stops[i].startX != stops[i].startX ||
          oldDelegate.stops[i].startY != stops[i].startY ||
          oldDelegate.stops[i].endX != stops[i].endX ||
          oldDelegate.stops[i].endY != stops[i].endY ||
          oldDelegate.stops[i].type != stops[i].type) {
        return true;
      }
    }
    return false;
  }
}

/// 渐变停止点数据模型
class GradientStop {
  Color color;
  double position;
  double startX;
  double startY;
  double endX;
  double endY;
  String type; // 'linear' 或 'radial'

  GradientStop({
    required this.color,
    this.position = 0.0,
    this.startX = 0.5,
    this.startY = 0.0,
    this.endX = 0.5,
    this.endY = 1.0,
    this.type = 'linear',
  });

  // 从 JSON Map 构造（用于从数据库恢复）
  factory GradientStop.fromJson(Map<String, dynamic> json) {
    final hex = json['color'] as String? ?? '#808080';
    return GradientStop(
      color: Color(int.parse(hex.replaceFirst('#', 'FF'), radix: 16)),
      position: (json['position'] as num?)?.toDouble() ?? 0.0,
      startX: (json['startX'] as num?)?.toDouble() ?? 0.5,
      startY: (json['startY'] as num?)?.toDouble() ?? 0.0,
      endX: (json['endX'] as num?)?.toDouble() ?? 0.5,
      endY: (json['endY'] as num?)?.toDouble() ?? 1.0,
      type: json['type'] as String? ?? 'linear',
    );
  }

  // 转换为 JSON Map（用于保存到数据库）
  Map<String, dynamic> toJson() {
    final hex = '#${color.toARGB32().toRadixString(16).substring(2).padLeft(6, '0')}';
    return {
      'color': hex,
      'position': position,
      'startX': startX,
      'startY': startY,
      'endX': endX,
      'endY': endY,
      'type': type,
    };
  }

  // 创建副本（用于不可变更新）
  GradientStop copyWith({
    Color? color,
    double? position,
    double? startX,
    double? startY,
    double? endX,
    double? endY,
    String? type,
  }) {
    return GradientStop(
      color: color ?? this.color,
      position: position ?? this.position,
      startX: startX ?? this.startX,
      startY: startY ?? this.startY,
      endX: endX ?? this.endX,
      endY: endY ?? this.endY,
      type: type ?? this.type,
    );
  }
}