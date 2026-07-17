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

  // ===== 保存菜单 =====
  void _showSaveMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final bakeable = _currentElements.where(_isBakeableElement).length;
        final skipped = _currentElements.length - bakeable;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '保存成果',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF111116),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '当前工作台元素：${_currentElements.length} 个 · 可烘焙视觉层：$bakeable 个 · 跳过：$skipped 个',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF777783),
                  ),
                ),
                const SizedBox(height: 14),
                _buildSaveMenuTile(
                  icon: Icons.save_alt_rounded,
                  title: '保存工作台草稿',
                  subtitle: '只保存当前画布，方便下次继续编辑；不加入资产库。',
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveWorkspaceDraft();
                  },
                ),
                _buildSaveMenuTile(
                  icon: Icons.dashboard_customize_rounded,
                  title: '保存为复合组件',
                  subtitle: '把当前画布元素保存为一个通用组件，子元素运行时仍独立存在。',
                  onTap: () {
                    Navigator.pop(ctx);
                    _saveCurrentWorkspaceAsComposite();
                  },
                ),
                _buildSaveMenuTile(
                  icon: Icons.layers_clear_rounded,
                  title: '烘焙为面原子',
                  subtitle: '只合成可烘焙视觉层，文本/数据/交互热区会被跳过。',
                  onTap: bakeable == 0
                      ? null
                      : () {
                          Navigator.pop(ctx);
                          _bakeCurrentWorkspaceAsAtom();
                        },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaveMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    final enabled = onTap != null;
    return Card(
      elevation: 0,
      color: enabled ? const Color(0xFFF6F6F9) : const Color(0xFFE9E9EF),
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ListTile(
        enabled: enabled,
        leading: Icon(
          icon,
          color: enabled ? const Color(0xFFFF4081) : const Color(0xFFAAAAB4),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF111116),
          ),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: Color(0xFF777783)),
        ),
        onTap: onTap,
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
