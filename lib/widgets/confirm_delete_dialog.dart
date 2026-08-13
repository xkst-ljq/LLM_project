import 'package:flutter/material.dart';

import '../shared/theme/app_theme_tokens.dart';

/// 统一的"确认删除"对话框。
///
/// 供角色库 / 世界书库 / 背景图库等删除时复用，保证视觉与交互一致：
/// 标题"确认删除" + 内容 + 取消 / 删除（danger 实心按钮）。
///
/// 返回 true 表示用户确认删除，false / null 表示取消。
Future<bool?> showConfirmDeleteDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = '删除',
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final tokens = AppThemeTokens.of(ctx);
      return AlertDialog(
        title: const Text('确认删除'),
        content: Text(
          message ?? title,
          style: TextStyle(
            color: tokens.textSecondary,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('取消', style: TextStyle(color: tokens.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              confirmLabel,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}
