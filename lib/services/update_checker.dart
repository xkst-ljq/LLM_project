import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../shared/theme/app_theme_tokens.dart';
import 'update_service.dart';

/// 更新检查的 UI 封装：弹更新提醒、跳转 Release 页。
class UpdateChecker {
  /// 是否正在检查（防重入：同一时刻只允许一次检查，避免重复点击弹多个弹窗）。
  static bool _checking = false;

  /// 检查更新；有新版且需要提醒时弹出提示。
  ///
  /// [showUpToDate] 为 true 时，即使没更新也弹"已是最新版"（用于手动检查）。
  /// 检查期间若再次调用会被忽略（防止快速点击弹多个弹窗）。
  static Future<void> checkAndPrompt(
    BuildContext context, {
    bool showUpToDate = false,
  }) async {
    if (_checking) return; // 进行中，忽略本次调用。
    _checking = true;
    try {
      await _checkAndPromptInner(context, showUpToDate: showUpToDate);
    } finally {
      _checking = false;
    }
  }

  static Future<void> _checkAndPromptInner(
    BuildContext context, {
    required bool showUpToDate,
  }) async {
    if (!context.mounted) return;
    final result = await UpdateService.check();

    if (!context.mounted) return;

    // 检查失败（网络异常 / 仓库无 Release）→ 提示失败，而非"已是最新"。
    if (result.error) {
      if (showUpToDate) {
        _showCheckFailed(context);
      }
      return;
    }

    if (!result.hasUpdate) {
      if (showUpToDate) {
        _showUpToDate(context);
      }
      return;
    }

    // 需要提醒（未对该版本提醒过）才弹；弹完记忆该版本。
    final shouldNotify = await UpdateService.shouldNotify(result);
    if (context.mounted && shouldNotify) {
      _showUpdateDialog(context, result);
      await UpdateService.markNotified(result.latestTag!);
    } else if (showUpToDate && context.mounted) {
      // 手动检查时，即使已提醒过也显示"有新版本"。
      _showUpdateDialog(context, result);
    }
  }

  static void _showCheckFailed(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline),
        title: const Text('检查更新失败'),
        content: const Text('无法连接到更新服务器，请检查网络后重试。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  static void _showUpToDate(BuildContext context) {
    final tokens = AppThemeTokens.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.check_circle, color: tokens.success),
        title: const Text('已是最新版本'),
        content: const Text('当前已经是最新版本，无需更新。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('好的'),
          ),
        ],
      ),
    );
  }

  static void _showUpdateDialog(BuildContext context, UpdateCheckResult result) {
    final tokens = AppThemeTokens.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.system_update_alt, color: tokens.accent),
        title: const Text('发现新版本'),
        content: Text(
          '检测到新版本 ${result.latestTag ?? ''}。\n\n'
          '点击「前往更新」将打开 GitHub Release 页面，可查看更新内容并下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openReleasePage(result.releaseUrl);
            },
            child: const Text('前往更新'),
          ),
        ],
      ),
    );
  }

  static Future<void> _openReleasePage(String? url) async {
    final target = url ?? kReleasePageUrl();
    try {
      final uri = Uri.parse(target);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // 打不开链接时静默失败。
    }
  }
}
