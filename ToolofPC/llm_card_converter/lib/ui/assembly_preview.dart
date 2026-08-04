import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:llm_ui_engine/llm_ui_engine.dart';

/// 角色卡里 UI（assembly）的预览面板。
///
/// ## 解决什么
///
/// 转译工具此前只能看文本结果，UI 是不可见的。
/// 而 UI 恰恰是最容易「静默出错」的部分——键名写错、类型写错、
/// 结构少一层，引擎读不到就用默认值，**不报错**
/// （见 `ASSEMBLY_HANDOFF.md` 3.5j）。
///
/// 没有预览，作者只能把卡导进主 App 才知道对不对；
/// 有了预览，转译完立刻能看到「实际长什么样」。
///
/// ## 与主项目的关系
///
/// 这里用的 `UIAssemblyRuntimeView` 就是主 App 聊天页在用的那一个，
/// 来自 `packages/llm_ui_engine`（同一份源码，不是拷贝）。
/// 因此**这里看到的效果 = 玩家实际看到的效果**，
/// 不存在「预览和真机不一样」的问题。
///
/// ## 输入
///
/// 直接吃角色卡的 `characterData`（`data/character.json` 形态），
/// 自己负责剥开三层嵌套：
///
/// ```
/// characterData
///   └── meta_json          String
///       └── ui_assemblies  List<String>
///           └── 单份 assembly（还是 String）
/// ```
///
/// 每一层解析失败都单独提示，而不是笼统报「没有 UI」——
/// 作者需要知道是「本来就没有」还是「有但写坏了」。
class AssemblyPreview extends StatefulWidget {
  const AssemblyPreview({
    super.key,
    required this.characterData,
    this.emptyHint = '这张卡没有 UI',
  });

  /// 角色卡数据（`data/character.json` 形态）。null 表示还没有转译结果。
  final Map<String, dynamic>? characterData;

  /// 卡里确实没有 UI 时的提示语。
  final String emptyHint;

  @override
  State<AssemblyPreview> createState() => _AssemblyPreviewState();
}

class _AssemblyPreviewState extends State<AssemblyPreview> {
  int _index = 0;

  /// 手动缩放倍率；`null` 表示「适配窗口」——自动等比缩放到刚好放进预览区。
  ///
  /// **默认是 1.0（1:1 实际尺寸）**：预览区宽高和 UI（PCB）宽高往往
  /// 不是同一个比例，1:1 才能看到真实字号/间距。UI 比预览区大时用滚动条
  /// 平移查看；想一眼看全貌就切「适配窗口」。
  double? _manualScale = 1.0;

  final ScrollController _hCtrl = ScrollController();
  final ScrollController _vCtrl = ScrollController();

  @override
  void didUpdateWidget(covariant AssemblyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了一张卡就回到第一份 UI，否则可能停在不存在的下标上。
    if (oldWidget.characterData != widget.characterData) {
      _index = 0;
      _setManual(1.0, jump: false); // 换卡回到 1:1
    }
  }

  @override
  void dispose() {
    _hCtrl.dispose();
    _vCtrl.dispose();
    super.dispose();
  }

  /// 步进缩放（每步 10%）。
  void _stepZoom(double delta) {
    final base = _manualScale ?? 1.0;
    _setManual((base + delta).clamp(0.1, 8.0));
  }

  /// 设置手动缩放倍率；`jump:false` 时保留当前滚动位置（换卡重置用）。
  void _setManual(double? v, {bool jump = true}) {
    setState(() => _manualScale = v);
    if (jump) {
      // 切换基准倍率后回到左上角，避免停在空白滚动区域让人以为卡住了。
      if (_hCtrl.hasClients) _hCtrl.jumpTo(0);
      if (_vCtrl.hasClients) _vCtrl.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _AssemblyExtraction.from(widget.characterData);

    if (parsed.error != null) {
      return _message(
        icon: Icons.error_outline,
        color: const Color(0xFFC62828),
        title: 'UI 数据读取失败',
        detail: parsed.error!,
      );
    }
    if (parsed.assemblies.isEmpty) {
      return _message(
        icon: Icons.crop_square_outlined,
        color: Colors.black38,
        title: widget.emptyHint,
        detail: '原卡没有可识别的界面元素时不会生成 UI —— 这是预期行为，不是错误。',
      );
    }

    final index = _index.clamp(0, parsed.assemblies.length - 1);
    final info = parsed.assemblies[index];

    return Column(
      children: [
        if (parsed.assemblies.length > 1) _buildSwitcher(parsed, index),
        _buildMeta(info, parsed.broken),
        Expanded(child: _buildStage(info)),
      ],
    );
  }

  /// 一张卡可以有多份 UI（四种 mode 各一），用分段控件切换。
  Widget _buildSwitcher(_AssemblyExtraction parsed, int index) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Wrap(
        spacing: 6,
        children: [
          for (var i = 0; i < parsed.assemblies.length; i++)
            ChoiceChip(
              label: Text(
                _modeLabel(parsed.assemblies[i].mode),
                style: const TextStyle(fontSize: 11),
              ),
              selected: i == index,
              onSelected: (_) => setState(() => _index = i),
            ),
        ],
      ),
    );
  }

  Widget _buildMeta(UIAssemblyInfo info, int broken) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${info.name} · ${_modeLabel(info.mode)} · '
            '${info.pcbWidth.toStringAsFixed(0)}×'
            '${info.pcbHeight.toStringAsFixed(0)} · '
            '${_pagesOf(info).length} 页 / ${_elementCount(info)} 个元件',
            style: const TextStyle(fontSize: 11, color: Color(0xFF666672)),
          ),
          if (broken > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '⚠ 有 $broken 份 UI 数据损坏，已跳过',
                style: const TextStyle(fontSize: 11, color: Color(0xFFC62828)),
              ),
            ),
        ],
      ),
    );
  }

  /// 渲染舞台。
  ///
  /// 两份职责分开：
  ///  - 顶部的缩放条负责「倍率调节」（适配窗口 / 100% / 步进 +/-）；
  ///  - 下方的预览区**按 UI 的真实比例等比缩放**渲染，绝不拉伸变形。
  ///
  /// 当 UI 按当前倍率渲染出来比预览区还大时，用双轴滚动条平移查看，
  /// 而不是把整个 UI 硬塞进一个小框——后者正是「UI 被压得很扁」的根源。
  Widget _buildStage(UIAssemblyInfo info) {
    return LayoutBuilder(
      builder: (context, box) {
        final viewport = Size(box.maxWidth, box.maxHeight);
        final fitScale = _fitScale(
          content: Size(info.pcbWidth, info.pcbHeight),
          box: viewport,
        );
        final scale = _manualScale ?? fitScale;
        final w = info.pcbWidth * scale;
        final h = info.pcbHeight * scale;

        return Column(
          children: [
            _buildZoomBar(info, fitScale),
            Expanded(
              child: Container(
                color: const Color(0xFFEDEDF2),
                child: ClipRect(child: _scrollableStage(
                  viewport: viewport,
                  contentWidth: w,
                  contentHeight: h,
                  child: _scaledUi(info, scale),
                )),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 顶部的缩放控制条。
  Widget _buildZoomBar(UIAssemblyInfo info, double fitScale) {
    final current = _manualScale ?? fitScale;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE0E0E6))),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove, size: 18),
            tooltip: '缩小',
            onPressed: () => _stepZoom(-0.1),
          ),
          SizedBox(
            width: 52,
            child: Text(
              '${(current * 100).round()}%',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add, size: 18),
            tooltip: '放大',
            onPressed: () => _stepZoom(0.1),
          ),
          const SizedBox(width: 4),
          _zoomChip('适配', _manualScale == null, () => _setManual(null)),
          const SizedBox(width: 4),
          _zoomChip('100%', _manualScale == 1.0, () => _setManual(1.0)),
          const Spacer(),
          const Icon(Icons.aspect_ratio, size: 14, color: Color(0xFF666672)),
          const SizedBox(width: 4),
          Text(
            '${info.pcbWidth.toStringAsFixed(0)}×${info.pcbHeight.toStringAsFixed(0)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF666672)),
          ),
        ],
      ),
    );
  }

  Widget _zoomChip(String label, bool selected, VoidCallback onTap) {
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: selected,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 8),
      selectedColor: Theme.of(context).colorScheme.primaryContainer,
      onSelected: (_) => onTap(),
    );
  }

  /// 按 `scale` 等比缩放出的 UI。外层 SizedBox 占住缩放后的真实尺寸，
  /// 内部用 Transform.scale 从左上角缩放，比例完全不变。
  Widget _scaledUi(UIAssemblyInfo info, double scale) {
    return SizedBox(
      width: info.pcbWidth * scale,
      height: info.pcbHeight * scale,
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.topLeft,
        child: DecoratedBox(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.16),
                blurRadius: 16,
              ),
            ],
          ),
          child: SizedBox(
            width: info.pcbWidth,
            height: info.pcbHeight,
            // 与主 App 聊天页用的是同一个组件、同一份源码。
            child: UIAssemblyRuntimeView(assemblyInfo: info),
          ),
        ),
      ),
    );
  }

  /// 双轴滚动舞台。
  ///
  /// 预览区至少要装下整个 viewport（UI 比 viewport 小时居中、不滚动）；
  /// UI 比 viewport 大时，容器取 UI 的实际尺寸，两个滚动条分别控横向/纵向。
  Widget _scrollableStage({
    required Size viewport,
    required double contentWidth,
    required double contentHeight,
    required Widget child,
  }) {
    final w = math.max(viewport.width, contentWidth) + 16;
    final h = math.max(viewport.height, contentHeight) + 16;
    return Scrollbar(
      controller: _hCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _hCtrl,
        scrollDirection: Axis.horizontal,
        child: Scrollbar(
          controller: _vCtrl,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _vCtrl,
            child: SizedBox(
              width: w,
              height: h,
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }

  double _fitScale({required Size content, required Size box}) {
    if (content.width <= 0 || content.height <= 0) return 1;
    if (box.width <= 0 || box.height <= 0) return 1;
    final s = (box.width / content.width) < (box.height / content.height)
        ? box.width / content.width
        : box.height / content.height;
    // 「适配」允许放大：这样 UI 总能铺满预览区，不再被压成一小块。
    return s < 0.01 ? 0.01 : s;
  }

  /// 解析页面列表。
  ///
  /// `UIAssemblyInfo` 存的是 `pagesJson`（字符串）而非 `pages` 对象列表
  /// ——这是三层嵌套结构的第三层，必须自己 decode。
  /// 与主项目 `_restoreAssemblyPages` 的读法保持一致。
  List<AssemblyPage> _pagesOf(UIAssemblyInfo info) {
    final raw = info.pagesJson.trim();
    if (raw.isEmpty || raw == '[]') return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((e) => AssemblyPage.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  int _elementCount(UIAssemblyInfo info) =>
      _pagesOf(info).fold<int>(0, (sum, p) => sum + p.elements.length);

  String _modeLabel(String mode) => switch (mode) {
        'opening' => '开场档案',
        'scene' => '全屏场景',
        'extra_sticky' => '常驻条',
        'extra_companion' => '伴生挂件',
        _ => mode,
      };

  Widget _message({
    required IconData icon,
    required Color color,
    required String title,
    required String detail,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: color),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              detail,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.black54,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 从角色卡数据里剥出 assembly 列表的结果。
///
/// 把「没有 UI」「UI 坏了」「读取过程出错」区分开——
/// 三者对作者的含义完全不同，笼统显示一句「无 UI」会误导排查方向。
class _AssemblyExtraction {
  const _AssemblyExtraction({
    this.assemblies = const [],
    this.broken = 0,
    this.error,
  });

  /// 成功解析的 UI。
  final List<UIAssemblyInfo> assemblies;

  /// 解析失败被跳过的份数（单份坏掉不影响其余）。
  final int broken;

  /// 整体读取失败的原因（如 meta_json 不是合法 JSON）。
  final String? error;

  static _AssemblyExtraction from(Map<String, dynamic>? card) {
    if (card == null) return const _AssemblyExtraction();

    // 第一层：meta_json 可能是字符串，也可能已经是 Map。
    final rawMeta = card['meta_json'];
    Map<String, dynamic> meta;
    try {
      if (rawMeta == null) return const _AssemblyExtraction();
      if (rawMeta is Map) {
        meta = Map<String, dynamic>.from(rawMeta);
      } else {
        final decoded = jsonDecode(rawMeta.toString());
        if (decoded is! Map) {
          return const _AssemblyExtraction(error: 'meta_json 不是对象');
        }
        meta = Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      return _AssemblyExtraction(error: 'meta_json 解析失败：$e');
    }

    // 第二层：ui_assemblies 是 List<String>，每个元素还是 JSON 字符串。
    final rawList = meta['ui_assemblies'];
    if (rawList == null) return const _AssemblyExtraction();
    if (rawList is! List) {
      return const _AssemblyExtraction(error: 'ui_assemblies 不是数组');
    }

    final out = <UIAssemblyInfo>[];
    var broken = 0;
    for (final item in rawList) {
      try {
        final info = item is Map
            ? UIAssemblyInfo.fromJson(Map<String, dynamic>.from(item))
            : UIAssemblyInfo.fromJsonString(item.toString());
        // fromJsonString 解析失败时返回 name='损坏数据' 的占位对象，
        // 不抛异常——必须显式识别，否则会渲染出一块空白面板。
        if (info.name == '损坏数据' && info.id.isEmpty) {
          broken++;
        } else {
          out.add(info);
        }
      } catch (_) {
        broken++;
      }
    }
    return _AssemblyExtraction(assemblies: out, broken: broken);
  }
}
