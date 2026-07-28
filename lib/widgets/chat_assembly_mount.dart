import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/character_meta.dart';
import '../models/session_state.dart';
import '../models/status_bar_field.dart';
import '../models/ui_assembly_info.dart';
import '../services/ui_engine/ui_semantic_role.dart';
import 'ui_assembly_runtime_view.dart';

/// A10-1：聊天页挂载 Assembly UI 的共性基础设施。
///
/// 各 mode 的差异只在「挂在哪、长什么样」，而以下部分是共用的：
///   - 从角色卡解析出对应 mode 的 UI 方案
///   - 与 `SessionState` 双向绑定（注入当前值 + 回写用户交互）
///   - 按 PCB 设计尺寸预留布局空间
///
/// 因此这里只负责「取出正确的方案并接好数据」，
/// 具体摆放位置交给调用方（A10-2 起逐个实现）。
class ChatAssemblyMount extends StatelessWidget {
  /// 角色卡元信息，从中读取 `uiAssemblies` 与状态栏字段定义。
  final CharacterMeta meta;

  /// 要挂载的 mode，如 `extra_sticky`。
  final String mode;

  /// 当前会话副本。UI 组件的初始显示与后续刷新都以它为准。
  final SessionState sessionState;

  /// 用户操作 UI 导致会话副本变化时回调，供上层落盘。
  final ValueChanged<SessionState>? onSessionStateChanged;

  /// 可用最大宽度。超出时由运行时等比缩小，不会溢出。
  final double? maxWidth;

  /// 是否启用整页滑动手势。挂件默认关闭——它覆盖在聊天内容上，
  /// 开启会挡住内部 slider 的拖动，且挂件通常只有一页。
  final bool enablePageGestures;

  /// 作者标记为「关闭 / 确认」的组件被点击时回调。
  final VoidCallback? onDismissRequested;

  const ChatAssemblyMount({
    super.key,
    required this.meta,
    required this.mode,
    required this.sessionState,
    this.onSessionStateChanged,
    this.maxWidth,
    this.enablePageGestures = false,
    this.onDismissRequested,
  });

  /// 取出该 mode 对应的 UI 方案；没有则返回 null。
  ///
  /// 一个角色卡同一 mode 只应有一个方案（opening / scene 在新建时就有唯一性
  /// 约束），这里取第一个有效的。
  static UIAssemblyInfo? resolveAssembly(CharacterMeta meta, String mode) {
    for (final raw in meta.uiAssemblies) {
      final info = UIAssemblyInfo.fromJsonString(raw);
      if (info.id.isEmpty) continue;
      if (info.mode != mode) continue;
      // 空方案没有任何页面内容，挂上去只会是一块空白。
      if (info.pagesJson.trim().isEmpty || info.pagesJson.trim() == '[]') {
        if (info.elementsJson.trim().isEmpty ||
            info.elementsJson.trim() == '[]') {
          continue;
        }
      }
      return info;
    }
    return null;
  }

  /// 该角色卡是否配置了此 mode 的可用 UI。
  static bool hasAssembly(CharacterMeta meta, String mode) =>
      resolveAssembly(meta, mode) != null;

  /// 作者是否标记了该 mode 的关键职责按钮。
  static bool hasKeyAction(CharacterMeta meta, String mode) {
    final info = resolveAssembly(meta, mode);
    if (info == null) return false;
    for (final page in _restorePages(info)) {
      if (UISemanticRole.hasKeyAction(page.elements)) return true;
    }
    return false;
  }

  /// 该 mode 的 UI 是否可以运行。
  ///
  /// opening / scene 会接管界面，缺少出口按钮会把玩家卡死，
  /// 因此没标记就不执行。常驻 UI 缺折叠按钮只是少一个功能，仍可运行。
  static bool canRun(CharacterMeta meta, String mode) {
    if (!UISemanticRole.blocksWithoutKeyAction(mode)) return true;
    return hasKeyAction(meta, mode);
  }

  /// 解析方案里的页面，供角色查找使用。
  static List<AssemblyPage> _restorePages(UIAssemblyInfo info) {
    final pages = <AssemblyPage>[];
    final raw = info.pagesJson.trim();
    if (raw.isNotEmpty && raw != '[]') {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          pages.addAll(
            decoded.whereType<Map>().map(
                  (item) =>
                      AssemblyPage.fromJson(Map<String, dynamic>.from(item)),
                ),
          );
        }
      } catch (_) {
        pages.clear();
      }
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    final info = resolveAssembly(meta, mode);
    if (info == null) return const SizedBox.shrink();
    // 缺少出口按钮的接管型 UI 不执行，避免玩家被卡死。
    if (!canRun(meta, mode)) return const SizedBox.shrink();

    final designWidth = info.pcbWidth
        .clamp(UIAssemblyInfo.minPcbWidth, UIAssemblyInfo.maxPcbWidth)
        .toDouble();
    final designHeight = info.pcbHeight
        .clamp(UIAssemblyInfo.minPcbHeight, UIAssemblyInfo.maxPcbHeight)
        .toDouble();

    // 按设计尺寸预留空间；宽度不足时等比缩小，保持不拉伸。
    final available = maxWidth ?? designWidth;
    final scale = available < designWidth ? available / designWidth : 1.0;

    return SizedBox(
      width: designWidth * scale,
      height: designHeight * scale,
      child: UIAssemblyRuntimeView(
        assemblyInfo: info,
        // 挂件不需要模糊背景铺满letterbox——它本身就是浮在聊天上的小窗。
        showBlurredBackdrop: false,
        enablePageGestures: enablePageGestures,
        onDismissRequested: onDismissRequested,
        sessionState: sessionState,
        statusFields: meta.statusBarFields,
        onSessionStateChanged: onSessionStateChanged,
      ),
    );
  }
}

/// 开场白 UI 的一次性展示状态。
///
/// 存在 `SessionState.overrides` 里而不是单独建表：
///   - 它随会话副本一起持久化，重启 App 不会重复弹出；
///   - 清空聊天记录时会一并清除，开场白重新出现——
///     这与「开场白属于本轮会话的开端」的语义一致。
class OpeningGreetingState {
  static const String _key = 'openingUIDismissed';

  /// 该角色的开场白 UI 是否已被玩家确认过。
  static bool isDismissed(SessionState session) =>
      session.overrides[_key] == true;

  /// 标记为已确认。返回 true 表示状态确实发生了变化。
  static bool markDismissed(SessionState session) {
    if (isDismissed(session)) return false;
    session.overrides[_key] = true;
    return true;
  }
}

/// 便于调用方按 mode 查询设计尺寸（用于预留布局空间 / 计算折叠位置）。
Size? assemblyDesignSize(CharacterMeta meta, String mode) {
  final info = ChatAssemblyMount.resolveAssembly(meta, mode);
  if (info == null) return null;
  return Size(
    info.pcbWidth
        .clamp(UIAssemblyInfo.minPcbWidth, UIAssemblyInfo.maxPcbWidth)
        .toDouble(),
    info.pcbHeight
        .clamp(UIAssemblyInfo.minPcbHeight, UIAssemblyInfo.maxPcbHeight)
        .toDouble(),
  );
}

/// 状态栏字段的便捷访问（挂载时需要传给运行时做数值 clamp）。
extension ChatAssemblyMountFields on CharacterMeta {
  List<StatusBarField> get mountStatusFields => statusBarFields;
}
