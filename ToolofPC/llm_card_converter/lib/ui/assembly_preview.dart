import 'dart:convert';

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

  /// 默认放大到 150% 预览，超出区域滚动查看。
  ///
  /// PC 工具窗口里 1:1 的 212px 伴生 UI 仍然偏小，不利于审稿；预览放大
  /// 只影响工作台查看，不改变导出的 UI 实际尺寸。作者仍可切回 100%
  /// 或适配窗口。
  double _previewScale = 1.5;

  @override
  void didUpdateWidget(covariant AssemblyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 换了一张卡就回到第一份 UI，否则可能停在不存在的下标上。
    if (oldWidget.characterData != widget.characterData) _index = 0;
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '${info.name} · ${_modeLabel(info.mode)} · '
                  '${info.pcbWidth.toStringAsFixed(0)}×'
                  '${info.pcbHeight.toStringAsFixed(0)} · '
                  '${_pagesOf(info).length} 页 / ${_elementCount(info)} 个元件',
                  style: const TextStyle(fontSize: 11, color: Color(0xFF666672)),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: DropdownButton<double>(
                  value: _previewScale,
                  isDense: true,
                  items: const [
                    DropdownMenuItem(value: 1.0, child: Text('100%')),
                    DropdownMenuItem(value: 1.5, child: Text('150%')),
                    DropdownMenuItem(value: 2.0, child: Text('200%')),
                    DropdownMenuItem(value: 0.0, child: Text('适配')),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => _previewScale = v);
                  },
                ),
              ),
            ],
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
  /// 默认 100% 原始尺寸，超出后滚动查看；只有作者手动切到“适配”时才
  /// 等比缩小。这样可以真实判断字体大小、按钮触点和间距。
  Widget _buildStage(UIAssemblyInfo info) {
    return LayoutBuilder(
      builder: (context, box) {
        final scale = _previewScale == 0.0
            ? _fitScale(
                content: Size(info.pcbWidth, info.pcbHeight),
                box: Size(box.maxWidth - 32, box.maxHeight - 32),
              )
            : _previewScale;
        final scaledW = info.pcbWidth * scale;
        final scaledH = info.pcbHeight * scale;
        return Container(
          color: const Color(0xFFEDEDF2),
          child: SingleChildScrollView(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: box.maxWidth,
                  minHeight: box.maxHeight,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: scaledW,
                      height: scaledH,
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  double _fitScale({required Size content, required Size box}) {
    if (content.width <= 0 || content.height <= 0) return 1;
    if (box.width <= 0 || box.height <= 0) return 1;
    final s = (box.width / content.width) < (box.height / content.height)
        ? box.width / content.width
        : box.height / content.height;
    return s > 1 ? 1 : s; // 只缩不放
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
