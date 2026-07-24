import 'package:flutter/material.dart';
import '../models/character_meta.dart';
import '../models/ui_assembly_info.dart';

/// 角色 UI 拼装列表页：浏览已有 UI，新建 UI（选模式后进拼装页）
class UIAssemblyListPage extends StatefulWidget {
  final CharacterMeta meta;
  final ValueChanged<CharacterMeta> onMetaChanged;

  const UIAssemblyListPage({
    super.key,
    required this.meta,
    required this.onMetaChanged,
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

  void _save() {
    final updatedMeta = widget.meta.copy();
    updatedMeta.uiAssemblies = _assemblies.where((a) => a.id.isNotEmpty).map((a) => a.toJsonString()).toList();
    widget.onMetaChanged(updatedMeta);
  }

  void _addNewUI() {
    final hasOpening = _assemblies.any((a) => a.mode == 'opening');
    final hasScene = _assemblies.any((a) => a.mode == 'scene');

    final options = <Map<String, dynamic>>[];
    if (!hasOpening) {
      options.add({'mode': 'opening', 'icon': Icons.auto_awesome_rounded, 'title': '开场白弹窗',
        'desc': '首次进入聊天时全屏展现，玩家确认后销毁。\n适合：角色设定确认、初始选项。'});
    }
    if (!hasScene) {
      options.add({'mode': 'scene', 'icon': Icons.gamepad_rounded, 'title': '场景 UI (全屏接管)',
        'desc': '替代传统对话气泡，整个屏幕变为游戏 HUD。\n适合：战斗界面、养成面板。'});
    }
    options.add({'mode': 'extra_sticky', 'icon': Icons.widgets_rounded, 'title': '常驻 UI',
      'desc': '浮在聊天上方，可折叠为悬浮球。\n适合：好感条、状态指示器。'});
    options.add({'mode': 'extra_companion', 'icon': Icons.chat_bubble_outline_rounded, 'title': '伴生 UI',
      'desc': '嵌入最新消息气泡下方，跟随聊天滚动。\n适合：评论区、记录面板。',
      'disabled': hasScene});

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
              if (hasOpening || hasScene) ...[
                const SizedBox(height: 4),
                Text(
                  hasOpening && hasScene ? '已达上限：已有开场白弹窗和场景 UI' : hasOpening ? '已达上限：已有开场白弹窗' : '已达上限：已有场景 UI',
                  style: const TextStyle(fontSize: 11, color: Color(0xFFE65100)),
                ),
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
          final info = UIAssemblyInfo(id: newId, mode: mode);
          _openAssemblyPage(info);
        },
      ),
    );
  }

  void _openAssemblyPage(UIAssemblyInfo info) async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => _CharacterAssemblyStubPage(assemblyInfo: info),
      ),
    );
    if (result != null && result.isNotEmpty) {
      // 保存返回的 UI 数据
      final updated = UIAssemblyInfo.fromJsonString(result);
      final idx = _assemblies.indexWhere((a) => a.id == updated.id);
      if (idx != -1) {
        _assemblies[idx] = updated;
      } else {
        _assemblies.add(updated);
      }
      setState(() {});
      _save();
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
                return Card(
                  elevation: 0,
                  color: Colors.white,
                  margin: const EdgeInsets.only(bottom: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: info.mode == 'opening'
                          ? const Color(0xFF7E57C2)
                          : info.mode == 'scene'
                              ? const Color(0xFFE65100)
                              : info.mode == 'extra_sticky'
                                  ? const Color(0xFF00838F)
                                  : const Color(0xFF00ACC1),
                      child: Icon(info.modeIcon, color: Colors.white, size: 20),
                    ),
                    title: Text(info.name, style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF111116))),
                    subtitle: Text(info.modeLabel, style: const TextStyle(fontSize: 11, color: Color(0xFF777783))),
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

/// 占位拼装页（A1 骨架：只显示模式名 + 保存按钮）
class _CharacterAssemblyStubPage extends StatefulWidget {
  final UIAssemblyInfo assemblyInfo;
  const _CharacterAssemblyStubPage({required this.assemblyInfo});

  @override
  State<_CharacterAssemblyStubPage> createState() => _CharacterAssemblyStubPageState();
}

class _CharacterAssemblyStubPageState extends State<_CharacterAssemblyStubPage> {
  late UIAssemblyInfo _info;

  @override
  void initState() {
    super.initState();
    _info = widget.assemblyInfo;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1E1E24),
      appBar: AppBar(
        backgroundColor: const Color(0xFF2A2A32),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_info.modeLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context, _info.toJsonString()),
            icon: const Icon(Icons.save_rounded, color: Color(0xFF00E676), size: 18),
            label: const Text('保存', style: TextStyle(color: Color(0xFF00E676))),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_info.modeIcon, size: 80, color: Colors.white24),
            const SizedBox(height: 16),
            Text('${_info.modeLabel} · 拼装画布', style: const TextStyle(color: Colors.white70, fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('画布即将在此渲染', style: TextStyle(color: Colors.white38, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
