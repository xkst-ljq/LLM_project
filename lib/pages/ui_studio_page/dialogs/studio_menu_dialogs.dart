part of '../ui_studio_page.dart';

/// 工作台顶部/底部菜单与基础列表选单弹窗构建子卷
mixin _StudioMenuDialogs on _UIStudioLogic {
  InputDecoration _softInputDecoration({String? label, String? helperText, String? hintText}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF2F2F6),
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF888896)),
      helperText: helperText,
      helperStyle: const TextStyle(fontSize: 10, color: Color(0xFF888896)),
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 11, color: Color(0xFFA0A0B0)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  // ===== 保存 =====
  void _showSaveMenu() {
    _showCompositeNameDialog();
  }



  // ===== 复合组件命名 =====
  void _showCompositeNameDialog() {
    final nameCtrl = TextEditingController(
      text: '复合组件 ${_assetService.getAllComposites().length + 1}',
    );
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('命名复合组件', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF111116))),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: _softInputDecoration(label: '组件名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF4081)),
            onPressed: () {
              final name = nameCtrl.text.trim();
              Navigator.pop(ctx);
              _saveCurrentWorkspaceAsComposite(name: name.isEmpty ? null : name);
            },
            child: const Text('保存', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===== 删除确认 =====
  void _confirmDeleteModule(UIModule module) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '删除资产',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111116),
          ),
        ),
        content: Text(
          '确定删除「${module.name}」吗？',
          style: const TextStyle(fontSize: 13, color: Color(0xFF555562)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4081),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _assetService.removeModule(module.id));
              _autoSave();
            },
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteComposite(UIComposite composite) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          '删除资产',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111116),
          ),
        ),
        content: Text(
          '确定删除「${composite.name}」吗？',
          style: const TextStyle(fontSize: 13, color: Color(0xFF555562)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消', style: TextStyle(color: Color(0xFF888896))),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFFF4081),
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _assetService.removeComposite(composite.id));
              _autoSave();
            },
            child: const Text(
              '删除',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
