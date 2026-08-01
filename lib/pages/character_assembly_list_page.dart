import 'package:flutter/material.dart';

import '../models/character_entry.dart';
import '../models/character_meta.dart';
import '../models/status_bar_field.dart';
import '../models/ui_assembly_info.dart';
import 'character_assembly_page.dart';

/// 角色 UI 拼装列表页：浏览已有 UI，新建 UI（选模式后进拼装页）
class UIAssemblyListPage extends StatefulWidget {
  final CharacterMeta meta;
  final ValueChanged<CharacterMeta> onMetaChanged;

  /// 角色卡的设定条目（只读参考）。
  /// A13-2 让数据通道能指向具体条目的子字段，需要知道卡片有哪些条目。
  final List<CharacterEntry> cardEntries;

  /// 卡类型（`character` / `system`），决定可选条目集合。
  final String cardType;

  const UIAssemblyListPage({
    super.key,
    required this.meta,
    required this.onMetaChanged,
    this.cardEntries = const <CharacterEntry>[],
    this.cardType = 'character',
  });

  @override
  State<UIAssemblyListPage> createState() => _UIAssemblyListPageState();
}

class _UIAssemblyListPageState extends State<UIAssemblyListPage> {
  late List<UIAssemblyInfo> _assemblies;

  @override
  void initState() {
    super.initState();
    _assemblies = widget.meta.uiAssemblies
        .map((s) => UIAssemblyInfo.fromJsonString(s))
        .where((a) => a.id.isNotEmpty)
        .toList();
  }

  void _save({List<StatusBarField>? statusFields}) {
    final updatedMeta = widget.meta.copy();
    updatedMeta.uiAssemblies = _assemblies.where((a) => a.id.isNotEmpty).map((a) => a.toJsonString()).toList();
    // 反写：作者在 UI 里改了绑定组件的初始值 / 量程，同步回状态栏定义。
    if (statusFields != null) {
      updatedMeta.statusBarFields = statusFields;
    }
    widget.onMetaChanged(updatedMeta);
  }

  /// 已存在的 mode 名称列表，用于「已达上限」提示。
  /// 每种 mode 只能有一个（运行时按 mode 查找，多建的不会被挂载）。
  List<String> _existingModeLabels({
    required bool hasOpening,
    required bool hasScene,
    required bool hasSticky,
    required bool hasCompanion,
  }) =>
      [
        if (hasOpening) '开场白弹窗',
        if (hasScene) '场景 UI',
        if (hasSticky) '常驻 UI',
        if (hasCompanion) '伴生 UI',
      ];

  void _addNewUI() {
    final hasOpening = _assemblies.any((a) => a.mode == 'opening');
    final hasScene = _assemblies.any((a) => a.mode == 'scene');
    // scene 与伴生**互斥**：scene 不渲染原生消息列表，伴生就没有宿主气泡。
    // 两个方向都要拦——先做伴生再加 scene 同样会造出无效组合。
    final hasCompanion = _assemblies.any((a) => a.mode == 'extra_companion');
    // 常驻 / 伴生同样是单例。
    //
    // 运行时 `ChatAssemblyMount.resolveAssembly` 按 mode 查找，
    // 遇到第一个匹配就 return——建了第二个也永远不会被挂载，
    // 作者却看不到任何提示，等于劳动被静默吞掉（用户提问点破）。
    //
    // 需要多个面板时用「叠加页 + 页面跳转」在同一个 UI 内实现，
    // 这也是用户的决策。
    final hasSticky = _assemblies.any((a) => a.mode == 'extra_sticky');

    final options = <Map<String, dynamic>>[];
    if (!hasOpening) {
      options.add({'mode': 'opening', 'icon': Icons.auto_awesome_rounded, 'title': '开场白弹窗',
        'desc': '首次进入聊天时全屏展现，玩家确认后销毁。\n适合：角色设定确认、初始选项。'});
    }
    if (!hasScene) {
      options.add({'mode': 'scene', 'icon': Icons.gamepad_rounded, 'title': '场景 UI (全屏接管)',
        'desc': hasCompanion
            ? '已有伴生 UI，两者互斥：场景会接管整个聊天页，伴生 UI 将失去所依附的消息气泡。'
            : '替代传统对话气泡，整个屏幕变为游戏 HUD。\n适合：战斗界面、养成面板。',
        'disabled': hasCompanion});
    }
    if (!hasSticky) {
      options.add({'mode': 'extra_sticky', 'icon': Icons.widgets_rounded, 'title': '常驻 UI',
        'desc': '浮在聊天上方，可折叠为悬浮球。\n适合：好感条、状态指示器。'});
    }
    if (!hasCompanion) {
      options.add({'mode': 'extra_companion', 'icon': Icons.chat_bubble_outline_rounded, 'title': '伴生 UI',
        'desc': hasScene
            ? '已有场景 UI，两者互斥：场景接管聊天页后没有消息气泡可供依附。'
            : '嵌入最新消息气泡下方，跟随聊天滚动。\n适合：评论区、记录面板。',
        'disabled': hasScene});
    }

    if (options.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('新建 UI 方案', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
              // 四种 mode 都是单例，已建的在这里列出来，
              // 免得作者对着少掉的选项猜为什么。
              if (_existingModeLabels(
                hasOpening: hasOpening,
                hasScene: hasScene,
                hasSticky: hasSticky,
                hasCompanion: hasCompanion,
              ).isNotEmpty) ...[
                const SizedBox(height: 4),
                Builder(builder: (context) {
                  // 先算出文案再插值：把多行方法调用塞进 ${} 里
                  // 可读性差，嵌套引号也容易出错。
                  final taken = _existingModeLabels(
                    hasOpening: hasOpening,
                    hasScene: hasScene,
                    hasSticky: hasSticky,
                    hasCompanion: hasCompanion,
                  ).join('、');
                  return Text(
                    '已达上限：已有$taken',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFFE65100)),
                  );
                }),
              ],
              const SizedBox(height: 4),
              const Text('选择 UI 类型后进入拼装画布', style: TextStyle(fontSize: 12, color: Color(0xFF888896))),
              const SizedBox(height: 16),
              ...options.map((opt) => Padding(
                  padding: EdgeInsets.only(bottom: opt == options.last ? 12 : 8),
                  child: _buildModeOption(
                    ctx,
                    opt['mode'] as String,
                    opt['icon'] as IconData,
                    opt['title'] as String,
                    opt['desc'] as String,
                    disabled: opt['disabled'] == true,
                  ),
                )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOption(BuildContext ctx, String mode, IconData icon, String title, String desc, {bool disabled = false}) {
    return Card(
      elevation: 0,
      color: disabled ? const Color(0xFFEEEEEE) : const Color(0xFFF6F6F9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        leading: Icon(icon, color: disabled ? const Color(0xFFBDBDBD) : const Color(0xFF651FFF), size: 28),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: disabled ? const Color(0xFFBDBDBD) : const Color(0xFF111116))),
        subtitle: Text(disabled ? '场景 UI 存在时强制常驻' : desc, style: const TextStyle(fontSize: 11, color: Color(0xFF777783), height: 1.3)),
        onTap: disabled ? null : () {
          Navigator.pop(ctx);
          final newId = 'ui_${DateTime.now().millisecondsSinceEpoch}';
          // 按 mode 取默认画布尺寸：常驻 / 伴生是挂件，
          // 用全屏尺寸起步会让作者一开始就把元件摆错位置。
          final size = UIAssemblyInfo.defaultPcbSizeFor(mode);
          final info = UIAssemblyInfo(
            id: newId,
            mode: mode,
            pcbWidth: size.width,
            pcbHeight: size.height,
          );
          _openAssemblyPage(info);
        },
      ),
    );
  }

  void _openAssemblyPage(UIAssemblyInfo info) async {
    final result = await Navigator.push<AssemblyEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CharacterAssemblyPage(
          assemblyInfo: info,
          statusFields: widget.meta.statusBarFields,
          cardEntries: widget.cardEntries,
          cardType: widget.cardType,
        ),
      ),
    );
    if (result != null && result.assemblyJson.isNotEmpty) {
      // 保存返回的 UI 数据
      final updated = UIAssemblyInfo.fromJsonString(result.assemblyJson);
      final idx = _assemblies.indexWhere((a) => a.id == updated.id);
      if (idx != -1) {
        _assemblies[idx] = updated;
      } else {
        _assemblies.add(updated);
      }
      setState(() {});
      _save(statusFields: result.statusFields);
      if (result.statusFields != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(milliseconds: 1800),
            behavior: SnackBarBehavior.floating,
            content: Text('绑定组件的改动已同步回状态栏字段'),
          ),
        );
      }
    }
  }

  void _editUI(UIAssemblyInfo info) {
    _openAssemblyPage(info);
  }

  void _deleteUI(int index) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('删除 UI 方案'),
        content: Text('确定删除「${_assemblies[index].name}」吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _assemblies.removeAt(index));
              _save();
            },
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F6F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Color(0xFF111116)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('UI 拼装方案', style: TextStyle(color: Color(0xFF111116), fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewUI,
        backgroundColor: const Color(0xFF651FFF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('新建 UI'),
      ),
      body: _assemblies.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dashboard_customize_rounded, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 12),
                  Text('还没有 UI 方案', style: TextStyle(fontSize: 15, color: Colors.grey[600])),
                  const SizedBox(height: 4),
                  const Text('点击下方按钮为角色创建 UI', style: TextStyle(fontSize: 12, color: Color(0xFF888896))),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _assemblies.length,
              itemBuilder: (context, index) {
                final info = _assemblies[index];
                // 同 mode 的第二个及之后**永远不会被运行时挂载**
                // （resolveAssembly 命中第一个就返回）。
                // 新建入口已经堵死，但历史数据里可能已经存在，
                // 必须显式标出来，否则作者会以为自己做的 UI 坏了。
                final shadowed = _assemblies
                    .sublist(0, index)
                    .any((a) => a.mode == info.mode);
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: shadowed
                          ? const Color(0xFFBDBDBD)
                          : info.mode == 'opening'
                          ? const Color(0xFF7E57C2)
                          : info.mode == 'scene'
                              ? const Color(0xFFE65100)
                              : info.mode == 'extra_sticky'
                                  ? const Color(0xFF00838F)
                                  : const Color(0xFF00ACC1),
                      child: Icon(info.modeIcon, color: Colors.white, size: 20),
                    ),
                    title: Text(info.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                    subtitle: shadowed
                        ? Text(
                            '${info.modeLabel} · 不会生效：已有同类型 UI',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFD32F2F)),
                          )
                        : Text(info.modeLabel,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF777783))),
                    trailing: PopupMenuButton<String>(
                      onSelected: (v) {
                        if (v == 'delete') _deleteUI(index);
                      },
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: Colors.red))),
                      ],
                    ),
                    onTap: () => _editUI(info),
                  ),
                );
              },
            ),
    );
  }
}